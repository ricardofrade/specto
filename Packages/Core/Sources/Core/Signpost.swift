import os

/// Signposts for the performance gates in CLAUDE.md. Names are fixed so XCTest
/// (`XCTOSSignpostMetric`) and Instruments measure the same intervals.
public enum Signpost {
    public static let subsystem = "dev.placeholder.specto.performance"
    /// Shows up in Instruments' Points of Interest track.
    public static let category = "PointsOfInterest"

    public enum Name: Sendable {
        case launchFirstFeedFrame
        case playbackTapToFirstFrame
        case playbackManifest
    }

    public struct Interval: Sendable {
        fileprivate let name: Name
        fileprivate let state: OSSignpostIntervalState
    }

    private static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    // OSSignposter needs StaticString names, hence the switches.
    public static func begin(_ name: Name) -> Interval {
        let id = signposter.makeSignpostID()
        let state = switch name {
        case .launchFirstFeedFrame: signposter.beginInterval("launch.firstFeedFrame", id: id)
        case .playbackTapToFirstFrame: signposter.beginInterval("playback.tapToFirstFrame", id: id)
        case .playbackManifest: signposter.beginInterval("playback.manifest", id: id)
        }
        return Interval(name: name, state: state)
    }

    public static func end(_ interval: Interval) {
        switch interval.name {
        case .launchFirstFeedFrame: signposter.endInterval("launch.firstFeedFrame", interval.state)
        case .playbackTapToFirstFrame: signposter.endInterval("playback.tapToFirstFrame", interval.state)
        case .playbackManifest: signposter.endInterval("playback.manifest", interval.state)
        }
    }
}
