# 0004 — tvOS app structure and CloudKit sync

Date: 2026-10-17. Status: accepted.

## Context

M7 adds the Apple TV app and ships the sync that M1 designed the schema for (ADR 0002). Three facts shaped the design:

- **tvOS has no persistent local storage.** Apps get a small `NSUserDefaults` and caches the system may purge. A database in Application Support isn't guaranteed to survive.
- **The iOS composition root is mostly platform-neutral.** Sources, routing, `play`/`plan`, expired-stream recovery, audio mode, SponsorBlock and DeArrow don't depend on the platform. PiP handoff, AirPlay switching, the Cast sender, MetricKit, CarPlay and offline audio are iPhone/iPad only, and MetricKit doesn't exist on tvOS.
- **Top Shelf runs in a separate extension process.** GRDB can share a database across processes, but only with coordinated locking and suspension handling.

## Decisions

1. **One composition root, two apps.** `App/Shared/` (the `AppEnvironment`, settings, licences view) is compiled into both `App/iOS` and `App/tvOS`. iOS-only members sit behind `#if os(iOS)`, and iOS-only behaviour lives in `App/iOS/Sources/AppEnvironment+iOS.swift`.
   - **Separate projects:** each platform has its own XcodeGen project, so a tvOS change can't break the iOS project file and vice versa.
2. **Feature models are shared, views are not.** The TV app reuses `FeedModel`, `SearchModel`, `ChannelModel` and `InstancesScreen`, but has its own focus-driven views: `.card` buttons, shelves, and a full-screen player driven by the Siri Remote.
   - **Packages:** Features and DesignSystem compile for tvOS. iOS-only modifiers go through `DesignSystem/PlatformModifiers.swift` rather than `#if` in every feature.
3. **On tvOS the database is a cache** (`Caches/Library/app.sqlite`). Losing it costs a refetch, never user data, because:
   - subscriptions and watch state come back from CloudKit (or YT Zero);
   - the feed refills from the instances.
4. **Top Shelf reads a JSON snapshot, not the database.**
   - **Writing:** the app writes `topshelf.json` (Continue Watching and Latest, at most 12 each) into the App Group container after feed changes and on backgrounding. It writes only when the content changed.
   - **Reading:** the extension decodes the snapshot and links each item to `dev.placeholder.specto.tv://watch?v=<id>`.
5. **CloudKit sync with `CKSyncEngine`**, in the private database, in one zone (`Library`).
   - **Records:** a `Subscription` and a `WatchState` record per row, named `<type>/<id>`.
   - **Pending changes:** a row is pending while `modifiedAt > uploadedAt`, so there's no outbox table and no triggers.
     - **Local writes** bump `modifiedAt`; writes that change nothing don't.
     - **Applying a fetched record** sets both columns, so it doesn't bounce back.
     - **Delivery:** a `ValueObservation` of the pending rows hands them to the engine.
   - **Conflicts:** last writer wins on `modifiedAt`. Deletions are tombstones (`isDeleted`), so a delete also carries a timestamp and wins or loses like any edit.
   - **System fields:** the server's change tag is kept with each row (`syncMetadata`), so uploads are updates rather than conflicts. A losing remote change still leaves its tag.
   - **Account changes:** sign-in, account switch, or the zone being deleted in iCloud settings mark everything for upload again. Sign-out keeps the library on the device.
   - **Isolation:** CloudKit types stay in `CloudRecords` and the `CloudSync` actor. `SyncStore` is plain GRDB and tested offline.
6. **Sync is opt-in at build time.** `CloudSync` starts only if Info.plist's `CloudKitContainer` (build setting `CLOUDKIT_CONTAINER`) names a container. Creating a `CKContainer` without the matching entitlement traps, so builds without the owner's iCloud setup simply don't sync.
   - **With YT Zero linked:** only instances sync (ADR 0006; this originally said sync stays off, ADR 0002).

## Consequences

- **Owner setup to turn sync on:**
  1. Create the iCloud container.
  2. Add the iCloud (CloudKit) and Push Notifications capabilities to both apps, plus the `remote-notification` background mode, so other devices' changes arrive promptly.
  3. Set `CLOUDKIT_CONTAINER`.
  4. Deploy the schema to production in the CloudKit console before release. Development and production schemas are separate.
- **Before App Store builds:** the App Group (`group.dev.placeholder.specto`) and the URL scheme are placeholders, like the bundle IDs. Replace them before signing for a device.
- **Watch history volume:** the first sign-in uploads all watch history. CloudKit batches it, but a very long history takes a while.
- **Not verified live:** sync against a real container needs the developer account, so it hasn't run against CloudKit yet. Conflict and mapping logic is covered by `SyncTests`.
