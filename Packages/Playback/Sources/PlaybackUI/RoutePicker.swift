import AVKit
import SwiftUI

/// The system AirPlay route picker.
public struct RoutePicker: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.activeTintColor = .tintColor
        picker.accessibilityLabel = String(localized: "AirPlay")
        return picker
    }

    public func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
