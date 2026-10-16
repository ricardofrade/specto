import SwiftUI
import UIKit

/// Continuous animation with a measured frame rate, for verifying 120 Hz on a ProMotion
/// device. The simulator renders at 60 Hz, so only the device reading is meaningful.
struct FrameRateCheck: View {
    @State private var monitor = FrameRateMonitor()

    var body: some View {
        VStack(spacing: 32) {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                GeometryReader { proxy in
                    Circle()
                        .fill(.tint)
                        .frame(width: 44, height: 44)
                        .offset(x: (proxy.size.width - 44) * abs(1 - 2 * phase))
                }
                .frame(height: 44)
            }
            Text(monitor.label)
                .font(.system(.largeTitle, design: .monospaced))
                .accessibilityIdentifier("perf.fps")
            Text("Expect ~120 on a ProMotion iPhone.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

@Observable
private final class FrameRateMonitor: NSObject {
    private(set) var label = "– fps"
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if windowStart == 0 { windowStart = link.timestamp }
        frames += 1
        let elapsed = link.timestamp - windowStart
        if elapsed >= 1 {
            label = "\(Int((Double(frames) / elapsed).rounded())) fps"
            frames = 0
            windowStart = link.timestamp
        }
    }
}
