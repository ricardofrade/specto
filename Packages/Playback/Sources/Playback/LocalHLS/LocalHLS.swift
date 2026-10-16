import AVFoundation
import UniformTypeIdentifiers
import Core

/// Plays adaptive MP4 streams (separate video and audio) in AVPlayer by writing HLS playlists
/// on device from each stream's segment index (M0 spike 6, `docs/spikes/local-hls.md`).
/// Unlocks AirPlay video and native Picture-in-Picture without a server-side remux.
public enum LocalHLS {
    public enum Failure: Error, Equatable {
        /// The stream has no init/index byte ranges, or isn't MP4 (webm can't go in HLS).
        case notIndexable
        case indexFetch(status: Int)
    }

    /// An asset plus the loader serving its playlists; keep both alive while playing.
    public struct Prepared: @unchecked Sendable {
        public let asset: AVURLAsset
        let loader: PlaylistLoader
    }

    public static func prepare(video: VideoStream, audio: AudioStream,
                               session: URLSession = .shared) async throws -> Prepared {
        guard video.container == .mp4, audio.container == .mp4,
              let videoInit = video.initRange, let videoIndex = video.indexRange,
              let audioInit = audio.initRange, let audioIndex = audio.indexRange else {
            throw Failure.notIndexable
        }
        async let videoSegments = segmentIndex(of: video.url, indexRange: videoIndex, session: session)
        async let audioSegments = segmentIndex(of: audio.url, indexRange: audioIndex, session: session)

        let videoRendition = HLSPlaylists.Rendition(url: video.url, initRange: videoInit, index: try await videoSegments)
        let audioRendition = HLSPlaylists.Rendition(url: audio.url, initRange: audioInit, index: try await audioSegments)
        let id = UUID().uuidString
        let base = "\(PlaylistLoader.scheme)://\(id)"
        let master = try HLSPlaylists.master(video: video, audio: audio,
                                             videoPlaylist: "\(base)/video.m3u8",
                                             audioPlaylist: "\(base)/audio.m3u8")
        let loader = PlaylistLoader(playlists: [
            "master.m3u8": Data(master.utf8),
            "video.m3u8": Data(HLSPlaylists.media(videoRendition).utf8),
            "audio.m3u8": Data(HLSPlaylists.media(audioRendition).utf8),
        ])
        let asset = AVURLAsset(url: URL(string: "\(base)/master.m3u8")!)
        asset.resourceLoader.setDelegate(loader, queue: PlaylistLoader.queue)
        return Prepared(asset: asset, loader: loader)
    }

    static func segmentIndex(of url: URL, indexRange: ByteRange, session: URLSession) async throws -> SegmentIndex {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(indexRange.start)-\(indexRange.end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 206 || status == 200 else { throw Failure.indexFetch(status: status) }
        // A server that ignores Range returns the whole file; the box still starts at indexRange.start.
        let bytes = status == 200 ? data.dropFirst(Int(indexRange.start)).prefix(Int(indexRange.length)) : data
        return try SegmentIndex(sidx: Data(bytes), indexRange: indexRange)
    }
}

/// Answers AVFoundation's requests for the generated playlists. Immutable after init, so the
/// delegate queue can read it without synchronisation.
final class PlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "localhls"
    static let queue = DispatchQueue(label: "player.localhls")
    private let playlists: [String: Data]

    init(playlists: [String: Data]) {
        self.playlists = playlists
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url, url.scheme == Self.scheme,
              let data = playlists[url.lastPathComponent] else { return false }
        if let info = request.contentInformationRequest {
            info.contentType = UTType.m3uPlaylist.identifier
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        request.dataRequest?.respond(with: data)
        request.finishLoading()
        return true
    }
}
