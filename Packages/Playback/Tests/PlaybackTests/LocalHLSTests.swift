import Foundation
import Testing
import Core
@testable import Playback

struct SegmentIndexTests {
    /// A `sidx` box: version, timescale, first_offset, and (size, duration) per reference.
    private func sidx(version: UInt8, timescale: UInt32, firstOffset: UInt64,
                      references: [(size: UInt32, duration: UInt32)]) -> Data {
        var body = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.bigEndian) { body.append(contentsOf: $0) } }
        append(version); body.append(contentsOf: [0, 0, 0])   // version + flags
        append(UInt32(1))                                    // reference_ID
        append(timescale)
        if version == 0 { append(UInt32(0)); append(UInt32(firstOffset)) } else { append(UInt64(0)); append(firstOffset) }
        append(UInt16(0)); append(UInt16(references.count))
        for reference in references {
            append(reference.size); append(reference.duration); append(UInt32(0x9000_0000))
        }
        var box = Data()
        withUnsafeBytes(of: UInt32(8 + body.count).bigEndian) { box.append(contentsOf: $0) }
        box.append(contentsOf: Array("sidx".utf8))
        return box + body
    }

    @Test func offsetsStartAfterTheBoxAndAccumulate() throws {
        let data = sidx(version: 0, timescale: 1000, firstOffset: 0,
                        references: [(1000, 5000), (2000, 5000), (1500, 4200)])
        #expect(data.count == 68)
        let index = try SegmentIndex(sidx: data, indexRange: ByteRange(start: 741, end: 741 + 68 - 1))
        #expect(index.segments.map(\.range) == [
            ByteRange(start: 809, end: 1808),
            ByteRange(start: 1809, end: 3808),
            ByteRange(start: 3809, end: 5308),
        ])
        #expect(index.segments.map(\.duration) == [5, 5, 4.2])
        #expect(index.maxDuration == 5)
    }

    @Test func version1HonoursFirstOffset() throws {
        let data = sidx(version: 1, timescale: 90_000, firstOffset: 100, references: [(500, 180_000)])
        let index = try SegmentIndex(sidx: data, indexRange: ByteRange(start: 0, end: Int64(data.count) - 1))
        #expect(index.segments.first?.range.start == Int64(data.count) + 100)
        #expect(index.segments.first?.duration == 2)
    }

    @Test func rejectsOtherBoxesAndTruncation() {
        var notSIDX = sidx(version: 0, timescale: 1, firstOffset: 0, references: [(1, 1)])
        notSIDX.replaceSubrange(4..<8, with: Array("moof".utf8))
        #expect(throws: SegmentIndex.ParseError.notSIDX("moof")) {
            try SegmentIndex(sidx: notSIDX, indexRange: ByteRange(start: 0, end: 10))
        }
        let truncated = sidx(version: 0, timescale: 1, firstOffset: 0, references: [(1, 1)]).prefix(30)
        #expect(throws: SegmentIndex.ParseError.truncated) {
            try SegmentIndex(sidx: Data(truncated), indexRange: ByteRange(start: 0, end: 29))
        }
    }
}

struct HLSPlaylistsTests {
    private let url = URL(string: "https://proxy.example/videoplayback?id=1")!

    @Test func mediaPlaylistUsesByteRanges() {
        let index = SegmentIndex(segments: [
            .init(range: ByteRange(start: 809, end: 1808), duration: 5),
            .init(range: ByteRange(start: 1809, end: 3808), duration: 4.2),
        ])
        let playlist = HLSPlaylists.media(.init(url: url, initRange: ByteRange(start: 0, end: 740), index: index))
        #expect(playlist == """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:5
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MAP:URI="https://proxy.example/videoplayback?id=1",BYTERANGE="741@0"
        #EXTINF:5.000,
        #EXT-X-BYTERANGE:1000@809
        https://proxy.example/videoplayback?id=1
        #EXTINF:4.200,
        #EXT-X-BYTERANGE:2000@1809
        https://proxy.example/videoplayback?id=1
        #EXT-X-ENDLIST

        """)
    }

    @Test func masterPlaylistDeclaresCodecsAndAudioGroup() throws {
        let video = VideoStream(url: url, codec: .h264, codecs: "avc1.640028", container: .mp4,
                                width: 1920, height: 1080, fps: 30, bitrate: 4_000_000, isHDR: false)
        let audio = AudioStream(url: url, codec: .aac, codecs: "mp4a.40.2", container: .mp4,
                                bitrate: 128_000, language: "en")
        let master = try HLSPlaylists.master(video: video, audio: audio,
                                             videoPlaylist: "localhls://x/video.m3u8",
                                             audioPlaylist: "localhls://x/audio.m3u8")
        #expect(master.contains(#"CODECS="avc1.640028,mp4a.40.2""#))
        #expect(master.contains("BANDWIDTH=4128000"))
        #expect(master.contains("RESOLUTION=1920x1080"))
        #expect(master.contains(#"LANGUAGE="en""#))
        #expect(master.contains(#"URI="localhls://x/audio.m3u8""#))
    }

    @Test func masterRequiresCodecStrings() {
        let video = VideoStream(url: url, codec: .h264, container: .mp4, width: 1, height: 1, fps: 1,
                                bitrate: nil, isHDR: false)
        let audio = AudioStream(url: url, codec: .aac, container: .mp4, bitrate: nil, language: nil)
        #expect(throws: HLSPlaylists.BuildError.missingCodecs) {
            try HLSPlaylists.master(video: video, audio: audio, videoPlaylist: "v", audioPlaylist: "a")
        }
    }
}
