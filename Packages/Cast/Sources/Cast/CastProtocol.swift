import Foundation

/// The Cast v2 wire format: each frame is a 4-byte big-endian length followed by a protobuf
/// `CastMessage`. Only the six fields senders use are modelled; no protobuf library needed.
///
/// ```
/// message CastMessage {
///   required ProtocolVersion protocol_version = 1;  // CASTV2_1_0 = 0
///   required string source_id = 2;
///   required string destination_id = 3;
///   required string namespace = 4;
///   required PayloadType payload_type = 5;          // STRING = 0
///   optional string payload_utf8 = 6;
/// }
/// ```
public struct CastMessage: Equatable, Sendable {
    public var sourceID: String
    public var destinationID: String
    public var namespace: String
    public var payload: String

    public init(sourceID: String = "sender-0", destinationID: String, namespace: String, payload: String) {
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.namespace = namespace
        self.payload = payload
    }

    public enum Namespace {
        public static let connection = "urn:x-cast:com.google.cast.tp.connection"
        public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        public static let receiver = "urn:x-cast:com.google.cast.receiver"
        public static let media = "urn:x-cast:com.google.cast.media"
    }

    // MARK: Encoding

    public func framed() -> Data {
        let body = encoded()
        var frame = withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) }
        frame.append(body)
        return frame
    }

    func encoded() -> Data {
        var data = Data()
        data.appendVarintField(1, 0)
        data.appendStringField(2, sourceID)
        data.appendStringField(3, destinationID)
        data.appendStringField(4, namespace)
        data.appendVarintField(5, 0)
        data.appendStringField(6, payload)
        return data
    }

    // MARK: Decoding

    public enum DecodeError: Error, Equatable { case truncated, unsupported }

    /// Splits complete frames off the front of `buffer`, leaving any partial frame in place.
    public static func takeFrames(from buffer: inout Data) throws -> [CastMessage] {
        var messages: [CastMessage] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.dropFirst(4).prefix(length)
            messages.append(try decode(Data(body)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return messages
    }

    static func decode(_ data: Data) throws -> CastMessage {
        var message = CastMessage(sourceID: "", destinationID: "", namespace: "", payload: "")
        var index = data.startIndex
        while index < data.endIndex {
            let key = try data.readVarint(at: &index)
            let field = key >> 3, wireType = key & 7
            switch wireType {
            case 0:
                _ = try data.readVarint(at: &index)
            case 2:
                let length = Int(try data.readVarint(at: &index))
                guard index + length <= data.endIndex else { throw DecodeError.truncated }
                let bytes = data[index..<index + length]
                index += length
                let text = String(decoding: bytes, as: UTF8.self)
                switch field {
                case 2: message.sourceID = text
                case 3: message.destinationID = text
                case 4: message.namespace = text
                case 6: message.payload = text
                default: break   // 7: binary payload, unused by the media namespace.
                }
            default:
                throw DecodeError.unsupported
            }
        }
        return message
    }
}

private extension Data {
    mutating func appendVarint(_ value: UInt64) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            append(byte)
        } while value != 0
    }

    mutating func appendVarintField(_ field: UInt64, _ value: UInt64) {
        appendVarint(field << 3 | 0)
        appendVarint(value)
    }

    mutating func appendStringField(_ field: UInt64, _ value: String) {
        let bytes = Data(value.utf8)
        appendVarint(field << 3 | 2)
        appendVarint(UInt64(bytes.count))
        append(bytes)
    }

    func readVarint(at index: inout Index) throws -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while true {
            guard index < endIndex, shift < 64 else { throw CastMessage.DecodeError.truncated }
            let byte = self[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }
}
