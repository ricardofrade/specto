import Foundation
import Core

/// Background downloads of audio for offline listening (M6). Ships only in builds with the
/// `OFFLINE_DOWNLOADS` condition: App Store and TestFlight builds leave it out (guideline 5.2.3,
/// `docs/distribution.md`).
///
/// Nonisolated: background `URLSession` delegates run on the session's queue. Mutable state is
/// guarded by `lock`.
public final class OfflineAudio: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let sessionIdentifier = "dev.placeholder.specto.offline-audio"

    private let store: DownloadStore
    public let directory: URL
    private let lock = NSLock()
    private var completion: (() -> Void)?
    private var session: URLSession!

    public init(database: AppDatabase, directory: URL? = nil) {
        store = DownloadStore(database)
        self.directory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? .temporaryDirectory).appending(path: "Offline", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsExpensiveNetworkAccess = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        // Excluded from iCloud backups: the audio can always be downloaded again.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = self.directory
        try? dir.setResourceValues(values)
    }

    /// Set by the app delegate when iOS relaunches the app for finished background transfers.
    public func setBackgroundCompletion(_ handler: @escaping () -> Void) {
        lock.withLock { completion = handler }
    }

    /// Starts (or restarts) a download. Stream URLs expire in hours, so download promptly.
    public func download(_ id: VideoID, audio: AudioStream) throws {
        if let existing = try store.entry(for: id), existing.state == .done, localFile(for: id) != nil { return }
        try store.setState(.downloading, for: id)
        let task = session.downloadTask(with: audio.url)
        task.taskDescription = id.rawValue
        task.countOfBytesClientExpectsToReceive = audio.contentLength ?? NSURLSessionTransferSizeUnknown
        task.resume()
    }

    public func localFile(for id: VideoID) -> URL? {
        guard let entry = try? store.entry(for: id), entry.state == .done, let name = entry.fileName else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Deletes the file and the entry, and cancels a download still in flight.
    public func remove(_ id: VideoID) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == id.rawValue { task.cancel() }
        }
        if let name = try? store.entry(for: id)?.fileName {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        try? store.remove(id)
    }

    /// Deletes watched downloads, then the least useful ones until under `limitBytes`.
    public func enforceLimit(_ limitBytes: Int64) {
        for entry in (try? store.watched()) ?? [] { remove(entry.videoID) }
        for entry in (try? store.evictionCandidates(limitBytes: limitBytes)) ?? [] { remove(entry.videoID) }
    }

    public var usedBytes: Int64 {
        ((try? store.all()) ?? []).filter { $0.state == .done }.reduce(0) { $0 + $1.bytes }
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let raw = downloadTask.taskDescription else { return }
        let id = VideoID(rawValue: raw)
        // Removed while downloading: don't bring it back.
        guard (try? store.entry(for: id)) != nil else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? store.setState(.failed, for: id)
            return
        }
        // The temporary file vanishes when this method returns: move it now.
        let name = "\(raw).m4a"
        let destination = directory.appending(path: name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            try store.setState(.done, for: id, fileName: name, bytes: bytes)
        } catch {
            try? store.setState(.failed, for: id)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let raw = task.taskDescription else { return }
        let id = VideoID(rawValue: raw)
        guard let entry = try? store.entry(for: id), entry.state != .done else { return }
        try? store.setState(.failed, for: id)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock { () -> (() -> Void)? in
            defer { completion = nil }
            return completion
        }
        DispatchQueue.main.async { handler?() }
    }
}
