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
