import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Thumbnails, decoded and downsampled to the exact pixel size off the main thread.
/// Memory cache for scroll-back, disk cache of the *downsampled* bytes so a cold launch
/// decodes small files, and coalescing so a cell and its prefetch share one download.
public actor ImagePipeline {
    public static let shared = ImagePipeline()

    /// Adds per-host headers (for example YT Zero's Bearer token for its image cache).
    public typealias RequestDecorator = @Sendable (URL) -> URLRequest

    private let session: URLSession
    private let disk: URL
    private var decorate: RequestDecorator = { URLRequest(url: $0) }
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    nonisolated private let memory = MemoryCache()

    /// - Parameter directory: where downsampled images are kept; `Caches/Thumbnails` by default.
    public init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        disk = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? .temporaryDirectory)
            .appending(path: "Thumbnails", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
    }

    public func setRequestDecorator(_ decorator: @escaping RequestDecorator) {
        decorate = decorator
    }

    /// Synchronous memory lookup, so cells that scroll back in render on their first frame.
    public nonisolated func cached(_ url: URL, pixelSize: CGSize) -> UIImage? {
        memory.image(for: Self.key(url, pixelSize))
    }

    public func image(_ url: URL, pixelSize: CGSize) async -> UIImage? {
        let key = Self.key(url, pixelSize)
        if let hit = memory.image(for: key) { return hit }
        if let task = inFlight[key] { return await task.value }

        let file = disk.appending(path: Self.fileName(key))
        let request = decorate(url)
        let session = self.session, memory = self.memory
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            // Disk first: already downsampled, so decoding is cheap.
            if let data = try? Data(contentsOf: file), let image = Self.decode(data, maxPixel: nil) {
                memory.insert(image, for: key)
                // Marks it recently used, so trimming removes the oldest first.
                try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))
                return image
            }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  let image = Self.decode(data, maxPixel: max(pixelSize.width, pixelSize.height)) else { return nil }
            memory.insert(image, for: key)
            if let jpeg = image.jpegData(compressionQuality: 0.82) {
                try? jpeg.write(to: file, options: .atomic)
            }
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    /// Keeps the disk cache under `maxBytes`, removing the least recently used images first.
    /// Run at low priority after launch.
    public nonisolated func trimDiskCache(maxBytes: Int = 300 * 1024 * 1024) async {
        let disk = self.disk
        await Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: disk, includingPropertiesForKeys: Array(keys))
            else { return }
            var entries = files.compactMap { file -> (URL, Date, Int)? in
                guard let values = try? file.resourceValues(forKeys: keys) else { return nil }
                return (file, values.contentModificationDate ?? .distantPast, values.totalFileAllocatedSize ?? 0)
            }
            var total = entries.reduce(0) { $0 + $1.2 }
            guard total > maxBytes else { return }
            entries.sort { $0.1 < $1.1 }
            for (file, _, size) in entries where total > maxBytes {
                try? FileManager.default.removeItem(at: file)
                total -= size
            }
        }.value
    }

    /// Warm images likely to scroll into view; cancelled implicitly by the cache filling.
    public func prefetch(_ urls: [URL], pixelSize: CGSize) {
        for url in urls where memory.image(for: Self.key(url, pixelSize)) == nil {
            Task(priority: .utility) { _ = await image(url, pixelSize: pixelSize) }
        }
    }

    /// ImageIO thumbnailing decodes straight to the target size, never the full image.
    nonisolated static func decode(_ data: Data, maxPixel: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maxPixel, maxPixel > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    nonisolated static func key(_ url: URL, _ size: CGSize) -> String {
        "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))"
    }

    nonisolated static func fileName(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}

/// `NSCache` is thread-safe; this wrapper just types it.
private final class MemoryCache: @unchecked Sendable {
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// A remote thumbnail that fills its frame. Give it the frame's point size; it requests
/// exactly that many pixels.
public struct RemoteImage: View {
    private let url: URL?
    private let pointSize: CGSize
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    public init(_ url: URL?, pointSize: CGSize) {
        self.url = url
        self.pointSize = pointSize
    }

    private var pixelSize: CGSize { CGSize(width: pointSize.width * scale, height: pointSize.height * scale) }

    public var body: some View {
        Group {
            if let image = image ?? url.flatMap({ ImagePipeline.shared.cached($0, pixelSize: pixelSize) }) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Tokens.Colors.thumbnailPlaceholder
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ImagePipeline.shared.cached(url, pixelSize: pixelSize)
            if image == nil { image = await ImagePipeline.shared.image(url, pixelSize: pixelSize) }
        }
    }
}
