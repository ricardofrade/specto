import SwiftUI
import Core
import Playback
import PlaybackUI

/// M0 spike 7: Picture-in-Picture for mpv playback via an AVPlayer handoff. Loads a video from
/// a Piped instance (`-DebugPipedURL <api> -DebugVideoID <id>`), plays it with mpv, then
/// hands off to PiP and back, reporting the measured timings.
struct PiPSpike: View {
    @State private var session = PlaybackSession(resumeStore: NoResume()) { _ in MPVEngine() }
    @State private var handoff = PictureInPictureHandoff()
    @State private var page: WatchPage?
    @State private var status = "loading"
    @State private var pipHost = LayerBox()

    var body: some View {
        VStack(spacing: 16) {
            PlayerSurface(session: session)
                .aspectRatio(16 / 9, contentMode: .fit)
            // AVPlayerLayer for PiP lives here; PiP needs it in the window hierarchy.
            LayerHostView(box: pipHost)
                .frame(width: 160, height: 90)
            Text(status)
                .font(.footnote.monospacedDigit())
                .accessibilityIdentifier("pip.status")
            HStack {
                Button("Start PiP") { Task { await startPiP() } }
                Button("Stop PiP") { handoff.stop() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .task { await load() }
    }

    private func load() async {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let api = value("-DebugPipedURL").flatMap(URL.init(string:)), let id = value("-DebugVideoID") else {
            status = "pass -DebugPipedURL and -DebugVideoID"
            return
        }
        do {
            let source = PipedSource(instance: InstanceConfig(kind: .piped, displayName: "Piped", apiURL: api))
            let page = try await source.watchPage(for: VideoID(rawValue: id))
            self.page = page
            let request = try PlaybackPlanner(selector: FormatSelector(capabilities: DecodeCapabilities()))
                .request(for: page, mode: .video, maxDisplayHeight: 1080, throughputBitsPerSecond: nil, allowHDR: false)
            await session.play(NowPlayingItem(videoID: page.manifest.videoID, title: page.details.summary.title,
                                              channelName: "", artworkURL: nil), request)
            status = "mpv playing"
        } catch {
            status = "load failed: \(error)"
        }
    }

    private func startPiP() async {
        guard let manifest = page?.manifest, let layer = pipHost.view?.layer,
              let video = manifest.videoStreams.filter({ $0.container == .mp4 && $0.codec == .h264 && $0.height <= 1080 })
                .max(by: { $0.height < $1.height }),
              let audio = manifest.audioStreams.first(where: { $0.codec == .aac && $0.isOriginal }) else {
            status = "no H.264 + AAC streams"
            return
        }
        handoff.onStop = { position in
            Task {
                await session.seek(to: position, precise: true)
                session.resume()
                status = "returned to mpv at \(position.formatted(.time(pattern: .minuteSecond)))"
            }
        }
        do {
            let from = session.position
            try await handoff.start(video: video, audio: audio, at: from, in: layer)
            session.pause()
            if let timing = handoff.lastTiming {
                status = "pip active · prepare \(ms(timing.prepare)) · ready \(ms(timing.ready)) · total \(ms(timing.total))"
            }
        } catch {
            status = "pip failed: \(error)"
        }
    }

    private func ms(_ duration: Duration) -> String {
        "\(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000) ms"
    }
}

@Observable
final class LayerBox {
    @ObservationIgnored var view: UIView?
}

private struct LayerHostView: UIViewRepresentable {
    let box: LayerBox

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        box.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

private struct NoResume: ResumeStore {
    func position(for id: VideoID) async -> Duration? { nil }
    func save(_ position: Duration, duration: Duration?, for id: VideoID) async {}
}
