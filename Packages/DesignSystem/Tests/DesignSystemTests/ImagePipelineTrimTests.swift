import Foundation
import Testing
@testable import DesignSystem

@Suite struct ImagePipelineTrimTests {
    @Test func trimRemovesLeastRecentlyUsedFirst() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pipeline = ImagePipeline(directory: directory)
        let now = Date.now
        for (name, age) in [("old", 300.0), ("middle", 200.0), ("new", 100.0)] {
            let file = directory.appending(path: "\(name).jpg")
            try Data(repeating: 1, count: 64 * 1024).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                                                  ofItemAtPath: file.path(percentEncoded: false))
        }
        await pipeline.trimDiskCache(maxBytes: 150 * 1024)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
        #expect(left == ["middle.jpg", "new.jpg"])
    }
}
