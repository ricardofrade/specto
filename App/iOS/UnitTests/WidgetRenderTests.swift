import SwiftUI
import Testing
import WidgetKit
@testable import Specto

/// Renders the Continue Watching widget at each size to PNGs, for design review without a Home
/// Screen. The paths are printed.
@MainActor
struct WidgetRenderTests {
    private let items = [
        HomeSnapshot.Item(id: "a", title: "Blender Conference 2026 Recap", imageURL: nil, progress: 0.4, channelName: "Blender"),
        HomeSnapshot.Item(id: "b", title: "The Future of Rendering — BCON26", imageURL: nil, progress: 0.75, channelName: "Blender"),
        HomeSnapshot.Item(id: "c", title: "Audio Nodes: Live Sound, Living Geometry", imageURL: nil, progress: 0.1, channelName: "Blender"),
        HomeSnapshot.Item(id: "d", title: "Closing Event — BCON26", imageURL: nil, progress: 0.9, channelName: "Blender"),
    ]

    @Test(arguments: [(WidgetFamily.systemSmall, CGSize(width: 170, height: 170)),
                      (.systemMedium, CGSize(width: 364, height: 170)),
                      (.systemLarge, CGSize(width: 364, height: 382))])
    func rendersEveryFamily(_ family: WidgetFamily, _ size: CGSize) throws {
        let view = ContinueWatchingView(entry: Entry(date: .now, items: items, isContinue: true), familyOverride: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.95), in: .rect(cornerRadius: 22))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(family).png")
        try #require(image.pngData()).write(to: url)
        print("WIDGET RENDER: \(url.path(percentEncoded: false))")
    }
}
