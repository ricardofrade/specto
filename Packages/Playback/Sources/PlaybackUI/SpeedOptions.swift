import Foundation

/// The speeds the player offers, labelled once for the current locale ("1,5×" in Portuguese).
public enum SpeedOptions {
    public struct Option: Hashable, Sendable {
        public let rate: Float
        public let label: String
    }

    public static let all: [Option] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map { rate in
        Option(rate: rate, label: Double(rate).formatted(.number.precision(.fractionLength(0...2))) + "×")
    }

    public static func label(for rate: Float) -> String {
        all.first { $0.rate == rate }?.label ?? Double(rate).formatted() + "×"
    }
}
