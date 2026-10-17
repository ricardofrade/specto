import SwiftUI

/// One frame of a storyboard sprite sheet, cropped and scaled to `displayWidth`. The sheet is
/// decoded once at full size and cached; frames are views onto it.
public struct StoryboardFrameView: View {
    private let page: URL
    /// The frame's origin and size in the sheet, and the sheet's size, in pixels.
    private let origin: CGPoint
    private let frameSize: CGSize
    private let pageSize: CGSize
    private let displayWidth: CGFloat
    @State private var sheet: UIImage?

    public init(page: URL, origin: CGPoint, frameSize: CGSize, pageSize: CGSize, displayWidth: CGFloat) {
        self.page = page
        self.origin = origin
        self.frameSize = frameSize
        self.pageSize = pageSize
        self.displayWidth = displayWidth
    }

    public var body: some View {
        let scale = displayWidth / max(frameSize.width, 1)
        ZStack(alignment: .topLeading) {
            Tokens.Colors.thumbnailPlaceholder
            if let sheet {
                Image(uiImage: sheet)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                    .offset(x: -origin.x * scale, y: -origin.y * scale)
            }
        }
        .frame(width: displayWidth, height: frameSize.height * scale, alignment: .topLeading)
        .clipped()
        .task(id: page) {
            sheet = ImagePipeline.shared.cached(page, pixelSize: pageSize)
            if sheet == nil { sheet = await ImagePipeline.shared.image(page, pixelSize: pageSize) }
        }
    }
}
