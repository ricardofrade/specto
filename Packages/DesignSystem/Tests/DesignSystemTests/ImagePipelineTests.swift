import Testing
import UIKit
@testable import DesignSystem

struct ImagePipelineTests {
    /// A 1280×720 JPEG, the size of a typical YouTube "maxres" thumbnail.
    private func largeJPEG() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 1280, height: 720), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        }
    }

    @Test func decodesStraightToTheTargetSize() throws {
        let image = try #require(ImagePipeline.decode(largeJPEG(), maxPixel: 480))
        #expect(max(image.size.width, image.size.height) * image.scale == 480)
    }

    @Test func diskEntriesDecodeAtTheirStoredSize() throws {
        let image = try #require(ImagePipeline.decode(largeJPEG(), maxPixel: nil))
        #expect(image.size.width * image.scale == 1280)
    }

    @Test func cacheKeysIncludeTheSize() {
        let url = URL(string: "https://i.example/a.jpg")!
        #expect(ImagePipeline.key(url, CGSize(width: 320, height: 180))
            != ImagePipeline.key(url, CGSize(width: 640, height: 360)))
        #expect(ImagePipeline.fileName("a").count == 64 + 4)
    }

    @Test func garbageIsNotAnImage() {
        #expect(ImagePipeline.decode(Data("not an image".utf8), maxPixel: 100) == nil)
    }
}
