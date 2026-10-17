import Foundation
import Core

/// How tall a stream to plan for (ADR 0007): the person's limit for the current network,
/// Low Data Mode, the surface, or a quality picked by hand for this video.
public enum VideoQuality {
    /// The heights the player's picker and Settings offer, tallest first.
    public static let steps = [2160, 1440, 1080, 720, 480, 360]
    /// Low Data Mode's ceiling when the person's own limit is higher.
    public static let lowDataMaxHeight = 480

    /// - Parameters:
    ///   - surface: the render surface's height in pixels.
    ///   - manual: picked in the player; overrides everything, the surface included.
    ///   - limit: Settings' limit for the current network (Wi-Fi, or cellular), nil for none.
    ///   - isConstrained: Low Data Mode is on for the current network.
    public static func maxHeight(surface: Int, manual: Int?, limit: Int?, isConstrained: Bool) -> Int {
        if let manual { return manual }
        var height = surface
        if let limit { height = min(height, limit) }
        if isConstrained { height = min(height, lowDataMaxHeight) }
        return height
    }

    /// The heights this device can decode from `streams`, tallest first, for the picker.
    public static func heights(in streams: [VideoStream], capabilities: DecodeCapabilities, allowHDR: Bool) -> [Int] {
        let playable = streams.filter { stream in
            stream.height > 0 && stream.height <= capabilities.maxHeight(for: stream.codec) && (allowHDR || !stream.isHDR)
        }
        return Set(playable.map(\.height)).sorted(by: >)
    }

    /// "1080p", "4K".
    public static func label(_ height: Int) -> String {
        height >= 2160 ? "4K" : "\(height)p"
    }
}
