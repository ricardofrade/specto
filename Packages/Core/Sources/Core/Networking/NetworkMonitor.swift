import Foundation
import Network
import os

/// Whether the current network costs the person money or data: cellular or a personal hotspot
/// (`isExpensive`), or Low Data Mode (`isConstrained`). Read when planning playback.
public final class NetworkMonitor: Sendable {
    public struct Status: Sendable, Equatable {
        public var isExpensive: Bool
        public var isConstrained: Bool

        public init(isExpensive: Bool, isConstrained: Bool) {
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
        }
    }

    public static let shared = NetworkMonitor()

    private let state = OSAllocatedUnfairLock(initialState: Status(isExpensive: false, isConstrained: false))
    private let monitor = NWPathMonitor()

    private init() {
        let state = self.state
        monitor.pathUpdateHandler = { @Sendable path in
            state.withLock { $0 = Status(isExpensive: path.isExpensive, isConstrained: path.isConstrained) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.placeholder.specto.network", qos: .utility))
    }

    public var status: Status { state.withLock { $0 } }
}
