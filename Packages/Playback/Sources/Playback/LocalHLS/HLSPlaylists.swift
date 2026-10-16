import Foundation
import Core

/// HLS playlists written on device over a fragmented MP4's byte ranges, so AVPlayer can play
/// adaptive (separate video and audio) streams without a server remux (M0 spike 6).
enum HLSPlaylists {
    struct Rendition: Sendable {
        let url: URL
        let initRange: ByteRange
        let index: SegmentIndex
    }

    enum BuildError: Error, Equatable {
        case missingCodecs
    }

    /// - Parameters:
    ///   - videoPlaylist / audioPlaylist: the URIs the master playlist points at (custom scheme).
    static func master(video: VideoStream, audio: AudioStream,
                       videoPlaylist: String, audioPlaylist: String) throws -> String {
        guard let videoCodecs = video.codecs, let audioCodecs = audio.codecs else { throw BuildError.missingCodecs }
        let bandwidth = (video.bitrate ?? 5_000_000) + (audio.bitrate ?? 128_000)
        var streamInfo = "BANDWIDTH=\(bandwidth),CODECS=\"\(videoCodecs),\(audioCodecs)\",AUDIO=\"audio\""
        if video.width > 0, video.height > 0 { streamInfo += ",RESOLUTION=\(video.width)x\(video.height)" }
        if video.fps > 0 { streamInfo += ",FRAME-RATE=\(video.fps)" }
        if video.isHDR { streamInfo += ",VIDEO-RANGE=PQ" }
        let language = audio.language.map { ",LANGUAGE=\"\($0)\"" } ?? ""
        return """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES\(language),URI="\(audioPlaylist)"
        #EXT-X-STREAM-INF:\(streamInfo)
        \(videoPlaylist)

        """
    }

    static func media(_ rendition: Rendition) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(Int(rendition.index.maxDuration.rounded(.up)))",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MAP:URI=\"\(rendition.url.absoluteString)\",BYTERANGE=\"\(byteRange(rendition.initRange))\"",
        ]
        for segment in rendition.index.segments {
            lines.append("#EXTINF:\(String(format: "%.3f", segment.duration)),")
            lines.append("#EXT-X-BYTERANGE:\(byteRange(segment.range))")
            lines.append(rendition.url.absoluteString)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    /// HLS byte ranges are `length@offset`.
    private static func byteRange(_ range: ByteRange) -> String {
        "\(range.length)@\(range.start)"
    }
}
