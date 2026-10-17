import SwiftUI
import Playback

/// A data-saver limit in Settings (ADR 0007): "Best available", or a height.
struct QualityLimitPicker: View {
    let title: Text
    @Binding var limit: Int?

    var body: some View {
        Picker(selection: $limit) {
            Text("Best available").tag(Int?.none)
            ForEach(VideoQuality.steps.filter { $0 <= 1080 }, id: \.self) { height in
                Text(verbatim: VideoQuality.label(height)).tag(Optional(height))
            }
        } label: { title }
    }
}
