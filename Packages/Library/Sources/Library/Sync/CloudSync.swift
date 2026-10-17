import CloudKit
import Foundation
import os
import Core

/// Instances, subscriptions and watch state through the user's CloudKit private database.
/// While a YT Zero account owns the library (ADR 0002), only instances sync (ADR 0006). `CKSyncEngine` schedules the work; this actor
/// feeds it pending rows from `SyncStore` and applies what it fetches.
public actor CloudSync: CKSyncEngineDelegate {
    private let container: CKContainer
    private let store: SyncStore
    private var engine: CKSyncEngine?
    private var pendingObservation: Task<Void, Never>?
    private let log = Logger(subsystem: "dev.placeholder.specto", category: "sync")

    /// The container must be in the app's iCloud entitlement: CloudKit traps otherwise. The
    /// app passes the identifier only when its Info.plist names one (`CloudKitContainer`).
    public init(containerIdentifier: String, database: AppDatabase, types: Set<SyncStore.RecordType>,
                secrets: any SecretStore) {
        container = CKContainer(identifier: containerIdentifier)
        store = SyncStore(database, types: types, secrets: secrets)
    }

    public nonisolated var types: Set<SyncStore.RecordType> { store.types }

    /// Starts syncing and keeps the engine told about local edits.
    public func start() {
        guard engine == nil else { return }
        try? store.prepareScope()
        let saved = (try? store.engineState()).flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let engine = CKSyncEngine(.init(database: container.privateCloudDatabase, stateSerialization: saved, delegate: self))
        self.engine = engine
        if saved == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecords.zoneID))])
        }
        let pending = store.observePending()
        pendingObservation = Task { [weak self] in
            do {
                for try await keys in pending { await self?.enqueue(keys) }
            } catch {}
        }
    }

    /// Replaced by a sync of other types, or CloudKit isn't wanted any more: stop, keeping the saved state.
    public func stop() {
        pendingObservation?.cancel()
        pendingObservation = nil
        engine = nil
    }

    /// Foreground, pull to refresh: fetch and send now rather than when the engine decides.
    public func syncNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func enqueue(_ keys: [SyncStore.Key]) {
        guard let engine, !keys.isEmpty else { return }
        let known = Set(engine.state.pendingRecordZoneChanges)
        let changes = keys.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudRecords.recordID(for: $0)) }
            .filter { !known.contains($0) }
        if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) { try? store.saveEngineState(data) }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                // Everything here is new to this account: upload it all, then merge.
                try? store.resetForNewAccount()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecords.zoneID))])
                enqueue((try? store.pendingKeys()) ?? [])
            case .signOut:
                // Keep the library on this device; it uploads again when someone signs in.
                try? store.resetForNewAccount()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            // Our zone was deleted elsewhere (e.g. "Delete data from iCloud"): upload it all again.
            if changes.deletions.contains(where: { $0.zoneID == CloudRecords.zoneID }) {
                try? store.resetForNewAccount()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecords.zoneID))])
                enqueue((try? store.pendingKeys()) ?? [])
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                if let change = CloudRecords.change(from: modification.record) { _ = try? store.apply(change) }
            }
            for deletion in changes.deletions {
                if let key = CloudRecords.key(for: deletion.recordID) { try? store.forgetServerRecord(key) }
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                guard let key = CloudRecords.key(for: record.recordID),
                      let modifiedAt = record[CloudRecords.Field.modifiedAt] as? Date else { continue }
                try? store.markUploaded(key, modifiedAt: modifiedAt, systemFields: CloudRecords.systemFields(of: record))
            }
            for failure in sent.failedRecordSaves {
                handle(failure, engine: syncEngine)
            }

        case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let store = self.store
        // Returning nil drops a change whose row no longer exists.
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let key = CloudRecords.key(for: recordID), let change = try? store.change(for: key) else { return nil }
            return CloudRecords.record(for: change)
        }
    }

    // MARK: Conflicts

    private func handle(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, engine: CKSyncEngine) {
        let recordID = failure.record.recordID
        guard let key = CloudRecords.key(for: recordID) else { return }
        switch failure.error.code {
        case .serverRecordChanged:
            // Someone else saved first. The newer `modifiedAt` wins either way.
            guard let server = failure.error.serverRecord, let remote = CloudRecords.change(from: server) else { return }
            if (try? store.apply(remote)) == false {
                // Ours is newer: retry on top of the server's change tag (apply kept it).
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        case .zoneNotFound:
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecords.zoneID))])
            try? store.forgetServerRecord(key)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            // We had system fields for a record the server no longer has: save it as new.
            try? store.forgetServerRecord(key)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated:
            break   // The engine retries these itself.
        default:
            log.error("Couldn't save \(recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
        }
    }
}
