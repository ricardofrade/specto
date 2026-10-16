import Foundation
import Testing
import Core
@testable import Library

/// Delegate callbacks are driven directly with an unstarted task; nothing touches the network.
@Suite struct OfflineAudioTests {
    private func makeOffline() throws -> (OfflineAudio, DownloadStore) {
        let db = try AppDatabase.inMemory()
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (OfflineAudio(database: db, directory: dir), DownloadStore(db))
    }

    private func task(for id: VideoID) -> URLSessionTask {
        let task = URLSession.shared.dataTask(with: URL(string: "https://example.invalid/audio")!)
        task.taskDescription = id.rawValue
        return task
    }

    @Test func removedWhileDownloadingStaysRemoved() throws {
        let (offline, store) = try makeOffline()
        let id = VideoID(rawValue: "aqz-KE-bpKQ")
        try store.setState(.downloading, for: id)
        offline.remove(id)
        offline.urlSession(.shared, task: task(for: id), didCompleteWithError: URLError(.cancelled))
        #expect(try store.entry(for: id) == nil)
    }

    @Test func failedDownloadIsMarkedFailed() throws {
        let (offline, store) = try makeOffline()
        let id = VideoID(rawValue: "aqz-KE-bpKQ")
        try store.setState(.downloading, for: id)
        offline.urlSession(.shared, task: task(for: id), didCompleteWithError: URLError(.networkConnectionLost))
        #expect(try store.entry(for: id)?.state == .failed)
        #expect(offline.localFile(for: id) == nil)
    }

    @Test func lateErrorDoesNotUndoACompletedDownload() throws {
        let (offline, store) = try makeOffline()
        let id = VideoID(rawValue: "aqz-KE-bpKQ")
        try store.setState(.done, for: id, fileName: "aqz-KE-bpKQ.m4a", bytes: 10)
        offline.urlSession(.shared, task: task(for: id), didCompleteWithError: URLError(.unknown))
        #expect(try store.entry(for: id)?.state == .done)
    }
}
