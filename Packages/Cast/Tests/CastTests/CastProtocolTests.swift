import Foundation
import Network
import Testing
@testable import Cast

struct CastProtocolTests {
    @Test func messagesRoundTripThroughFraming() throws {
        let message = CastMessage(destinationID: "receiver-0", namespace: CastMessage.Namespace.receiver,
                                  payload: #"{"type":"LAUNCH","appId":"CC1AD845","requestId":1}"#)
        var stream = message.framed() + message.framed()
        let decoded = try CastMessage.takeFrames(from: &stream)
        #expect(decoded == [message, message])
        #expect(stream.isEmpty)
    }

    @Test func partialFramesWaitForTheRest() throws {
        let frame = CastMessage(destinationID: "x", namespace: "n", payload: String(repeating: "a", count: 300)).framed()
        var stream = frame.prefix(100)
        #expect(try CastMessage.takeFrames(from: &stream).isEmpty)
        stream.append(frame.dropFirst(100))
        #expect(try CastMessage.takeFrames(from: &stream).count == 1)
    }

    /// Bytes for a known message, built by hand from the protobuf definition.
    @Test func encodingMatchesTheProtobufLayout() {
        let encoded = CastMessage(sourceID: "s", destinationID: "d", namespace: "n", payload: "p").encoded()
        #expect(Array(encoded) == [0x08, 0x00, 0x12, 0x01, 0x73, 0x1A, 0x01, 0x64, 0x22, 0x01, 0x6E,
                                   0x28, 0x00, 0x32, 0x01, 0x70])
    }
}

@MainActor
struct CastSessionTests {
    @Test func mediaStatusDrivesStateAndPosition() {
        let session = CastSession()
        session.handle(CastMessage(sourceID: "t", destinationID: "sender-0", namespace: CastMessage.Namespace.media,
                                   payload: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"PLAYING","currentTime":12.5}]}"#))
        #expect(session.state == .playing)
        #expect(session.position == 12.5)
        session.handle(CastMessage(sourceID: "t", destinationID: "sender-0", namespace: CastMessage.Namespace.media,
                                   payload: #"{"type":"MEDIA_STATUS","status":[{"playerState":"IDLE","idleReason":"ERROR"}]}"#))
        if case .failed = session.state {} else { Issue.record("Expected failure, got \(session.state)") }
    }
}

/// Talks to a real receiver on the local network, read-only (no app launched, nothing on
/// screen). Runs only with `CAST_PROBE=1`.
@MainActor
struct CastLiveProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAST_PROBE"] == "1"), .timeLimit(.minutes(1)))
    func discoversAndQueriesAReceiver() async throws {
        let discovery = CastDiscovery()
        discovery.start()
        let deadline = ContinuousClock.now + .seconds(10)
        while discovery.devices.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        let device = try #require(discovery.devices.first, "No Cast receivers found")
        print("Cast receivers: \(discovery.devices.map(\.name))")
        let status = try await CastSession.probe(device)
        print("RECEIVER_STATUS from \(device.name): \(status.prefix(300))")
        #expect(status.contains("RECEIVER_STATUS"))
        discovery.stop()
    }
}

/// Plays a real video on a receiver (it shows on the TV), once per kind of stream the instances
/// offer, to learn what the receiver accepts. Runs only with `CAST_DEVICE` (part of the
/// receiver's name), `PIPED_URL` and `INVIDIOUS_URL`; stops casting after each.
@MainActor
struct CastLivePlaybackTests {
    enum Source: String, CaseIterable, Sendable { case pipedHLS, pipedMuxed, invidiousDASH }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAST_DEVICE"] != nil), .timeLimit(.minutes(2)),
          .serialized, arguments: Source.allCases)
    func playsOnTheReceiver(_ source: Source) async throws {
        let environment = ProcessInfo.processInfo.environment
        let name = try #require(environment["CAST_DEVICE"])
        let (url, type) = try await Self.media(source, environment)

        let discovery = CastDiscovery()
        discovery.start()
        let deadline = ContinuousClock.now + .seconds(10)
        while !discovery.devices.contains(where: { $0.name.localizedCaseInsensitiveContains(name) }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        let device = try #require(discovery.devices.first { $0.name.localizedCaseInsensitiveContains(name) })

        let session = CastSession()
        session.cast(.init(url: url, contentType: type, title: "Big Buck Bunny", subtitle: source.rawValue,
                           imageURL: nil, startTime: 0), to: device)
        var states: [String] = []
        let playDeadline = ContinuousClock.now + .seconds(45)
        while ContinuousClock.now < playDeadline {
            let state = "\(session.state)"
            if states.last != state { states.append(state) }
            if session.state == .playing { break }
            if case .failed = session.state { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        if session.state == .playing { try await Task.sleep(for: .seconds(6)) }
        print("CAST RESULT \(source.rawValue): \(states.joined(separator: " → ")) position \(session.position)")
        session.stop()
        discovery.stop()
        try await Task.sleep(for: .seconds(2))
        #expect(states.contains("playing"), "\(source.rawValue): \(states)")
    }

    private static func media(_ source: Source, _ environment: [String: String]) async throws -> (URL, String) {
        let id = "aqz-KE-bpKQ"
        switch source {
        case .pipedHLS, .pipedMuxed:
            let piped = try #require(environment["PIPED_URL"].flatMap(URL.init(string:)))
            let (data, _) = try await URLSession.shared.data(from: piped.appending(path: "streams/\(id)"))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            if source == .pipedHLS {
                let link: String? = json["hls"] as? String
                return (try #require(link.flatMap { URL(string: $0) }), "application/x-mpegURL")
            }
            let streams = json["videoStreams"] as? [[String: Any]] ?? []
            let muxed = streams.first { ($0["videoOnly"] as? Bool) == false && ($0["mimeType"] as? String) == "video/mp4" }
            let link: String? = muxed?["url"] as? String
            return (try #require(link.flatMap { URL(string: $0) }, "No muxed MP4"), "video/mp4")
        case .invidiousDASH:
            let invidious = try #require(environment["INVIDIOUS_URL"].flatMap(URL.init(string:)))
            var components = try #require(URLComponents(url: invidious.appending(path: "api/manifest/dash/id/\(id)"),
                                                       resolvingAgainstBaseURL: false))
            components.queryItems = [URLQueryItem(name: "local", value: "true")]
            return (try #require(components.url), "application/dash+xml")
        }
    }
}
