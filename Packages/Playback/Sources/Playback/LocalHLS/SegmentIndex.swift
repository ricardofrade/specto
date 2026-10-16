import Foundation
import Core

/// Media segments of a fragmented MP4, read from its `sidx` box (ISO/IEC 14496-12 §8.16.3).
struct SegmentIndex: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let range: ByteRange
        let duration: Double
    }

    let segments: [Segment]

    var maxDuration: Double { segments.map(\.duration).max() ?? 0 }

    enum ParseError: Error, Equatable {
        case truncated
        case notSIDX(String)
        case hierarchical
    }

    /// - Parameters:
    ///   - data: the bytes of `indexRange`, which start with the `sidx` box.
    ///   - indexRange: where those bytes sit in the file; segment offsets are relative to the
    ///     first byte after the box.
    init(sidx data: Data, indexRange: ByteRange) throws {
        var reader = Reader(data: data)
        var boxSize = UInt64(try reader.uint32())
        let type = try reader.fourCC()
        guard type == "sidx" else { throw ParseError.notSIDX(type) }
        if boxSize == 1 { boxSize = try reader.uint64() }

        let version = try reader.uint8()
        try reader.skip(3)                       // flags
        try reader.skip(4)                       // reference_ID
        let timescale = Double(try reader.uint32())
        // earliest_presentation_time is skipped; first_offset is 32-bit in version 0, else 64-bit.
        let firstOffset: UInt64
        if version == 0 {
            try reader.skip(4)
            firstOffset = UInt64(try reader.uint32())
        } else {
            try reader.skip(8)
            firstOffset = try reader.uint64()
        }
        try self.init(reader: &reader, timescale: timescale, firstOffset: firstOffset,
                      anchor: UInt64(indexRange.start) + boxSize)
    }

    private init(reader: inout Reader, timescale: Double, firstOffset: UInt64, anchor: UInt64) throws {
        try reader.skip(2)                       // reserved
        let count = Int(try reader.uint16())
        var offset = anchor + firstOffset
        var segments: [Segment] = []
        segments.reserveCapacity(count)
        for _ in 0..<count {
            let reference = try reader.uint32()
            guard reference & 0x8000_0000 == 0 else { throw ParseError.hierarchical }
            let size = UInt64(reference & 0x7FFF_FFFF)
            let duration = Double(try reader.uint32()) / max(timescale, 1)
            try reader.skip(4)                   // SAP fields
            segments.append(Segment(range: ByteRange(start: Int64(offset), end: Int64(offset + size - 1)),
                                    duration: duration))
            offset += size
        }
        self.segments = segments
    }

    init(segments: [Segment]) {
        self.segments = segments
    }
}

/// Big-endian reader over box bytes.
private struct Reader {
    let data: Data
    var offset = 0

    mutating func skip(_ count: Int) throws {
        guard offset + count <= data.count else { throw SegmentIndex.ParseError.truncated }
        offset += count
    }

    mutating func uint8() throws -> UInt8 {
        try bytes(1).first!
    }

    mutating func uint16() throws -> UInt16 {
        try bytes(2).reduce(0) { $0 << 8 | UInt16($1) }
    }

    mutating func uint32() throws -> UInt32 {
        try bytes(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func uint64() throws -> UInt64 {
        try bytes(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func fourCC() throws -> String {
        String(decoding: try bytes(4), as: UTF8.self)
    }

    private mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw SegmentIndex.ParseError.truncated }
        let start = data.startIndex + offset
        offset += count
        return Array(data[start..<start + count])
    }
}
