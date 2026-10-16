import SwiftUI
import Core
import Playback
import PlaybackUI

/// M0 playback spike: paste separate video and audio stream URLs, play through mpv, and read
/// the decoder report. The player sheet can be dismissed and reopened while playback continues.
/// Prefill with `-DebugVideoURL <url> -DebugAudioURL <url>`.
struct PlayerDebug: View {
    @State private var session = PlaybackSession(resumeStore: NoResumeStore()) { _ in
        // AVPlayerEngine arrives in M4; mpv covers audio-only (vid=no) until then.
        MPVEngine()
    }
    @State private var videoURL = PlayerDebug.argument("-DebugVideoURL") ?? ""
    @State private var audioURL = PlayerDebug.argument("-DebugAudioURL") ?? ""
    @State private var showsPlayer = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Streams") {
                    TextField("Video stream URL", text: $videoURL, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Audio stream URL (optional)", text: $audioURL, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    Button("Play") { Task { await play() } }
                        .disabled(URL(string: videoURL) == nil)
                    Button("Open player") { showsPlayer = true }
                        .disabled(session.item == nil)
                    Button("Stop", role: .destructive) { session.stop() }
                        .disabled(session.item == nil)
                }
                Section("Now") {
                    DebugReadout(session: session)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Playback spike")
            .safeAreaInset(edge: .bottom) { StatusLine(session: session) }
            .sheet(isPresented: $showsPlayer) {
                VStack(spacing: 0) {
                    PlayerSurface(session: session)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .accessibilityIdentifier("debug.surface")
                    StatusLine(session: session)
                    Form { DebugReadout(session: session) }
                }
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-DebugAutoplay") {
                Task { await play() }
            }
        }
    }

    private func play() async {
        guard let video = URL(string: videoURL) else { return }
        let source: MediaSource
        if let audio = URL(string: audioURL), !audioURL.isEmpty {
            source = .adaptive(
                video: VideoStream(url: video, codec: .h264, container: .mp4, width: 0, height: 0,
                                   fps: 0, bitrate: nil, isHDR: false),
                audio: AudioStream(url: audio, codec: .aac, container: .mp4, bitrate: nil, language: nil))
        } else {
            source = .progressive(video)
        }
        let id = VideoID(rawValue: "debug")
        showsPlayer = true
        await session.play(NowPlayingItem(videoID: id, title: "Debug stream", channelName: "", artworkURL: nil),
                           PlaybackRequest(videoID: id, source: source, mode: .video))
    }

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// One line outside any Form (whose rows merge into a single accessibility element), so UI
/// tests can read state and position: "playing 0:31".
private struct StatusLine: View {
    let session: PlaybackSession

    var body: some View {
        Text("\(String(describing: session.state)) \(session.position.formatted(.time(pattern: .minuteSecond)))")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(8)
            .accessibilityIdentifier("debug.status")
    }
}

private struct DebugReadout: View {
    let session: PlaybackSession

    var body: some View {
        LabeledContent("State", value: String(describing: session.state))
        LabeledContent("Position", value: session.position.formatted(.time(pattern: .minuteSecond)))
        if let decoder = session.decoder {
            LabeledContent("Decoder", value: "\(decoder.codec.rawValue) · \(decoder.isHardware ? "hardware" : "software")")
                .accessibilityIdentifier("debug.decoder")
            LabeledContent("Resolution", value: "\(decoder.width)×\(decoder.height)")
        }
        if let stats = session.stats {
            LabeledContent("Dropped frames", value: "\(stats.droppedFrames)")
            LabeledContent("Buffered", value: stats.bufferedAhead.formatted(.units(allowed: [.seconds], width: .narrow)))
            if let throughput = stats.throughputBitsPerSecond {
                LabeledContent("Throughput", value: "\(Int(throughput / 1_000_000)) Mbit/s")
            }
        }
    }
}

/// The spike doesn't persist resume positions.
private struct NoResumeStore: ResumeStore {
    func position(for id: VideoID) async -> Duration? { nil }
    func save(_ position: Duration, for id: VideoID) async {}
}
