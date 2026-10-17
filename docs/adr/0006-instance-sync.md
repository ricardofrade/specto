# 0006 — Instances sync, with the YT Zero token in an encrypted field

Date: 2026-10-17. Status: accepted. Amends ADR 0004 (decision 6).

## Context

Typing an instance URL with the Siri Remote is slow, and YT Zero needs a pairing step on top of that. The user's instances are already on their iPhone, so the Apple TV should get them from there.

Before this ADR, CloudKit synced subscriptions and watch state only, and sync stopped entirely while a YT Zero account was linked (ADR 0002: the account owns the library). That is exactly when the TV needs the instance and its token.

## Decisions

1. **Instances are a third record type** (`Instance/<uuid>`), with the same rules as the others:
   - `modifiedAt`, `uploadedAt`, `syncMetadata` and an `isDeleted` tombstone (migration `v5-instance-sync`);
   - last writer wins.
   - **Removing** an instance now writes a tombstone instead of deleting the row, so the removal reaches other devices.
2. **The YT Zero token travels in the record's `encryptedValues`, not through iCloud Keychain.**
   - CloudKit encrypts these fields end to end, with keys held in the user's iCloud Keychain. Apple can't read them, and they never reach the database: `SyncStore` reads the token from the `SecretStore` when uploading, and writes it there when applying.
   - **Why not a synchronizable Keychain item (`kSecAttrSynchronizable`):**
     - The iOS and tvOS apps have different bundle IDs, so they'd need a shared keychain access group (team-prefixed entitlements on both).
     - The token would arrive independently of its instance, so the TV could see an instance without its token, or the reverse.
     - With `encryptedValues`, the token and the instance are one atomic record.
   - The token is written to the `SecretStore` before the row commits, so the app's instance observer always finds it when it rebuilds sources.
   - The token belongs to the phone's pairing, so the YT Zero dashboard shows the phone's device name for the TV too.
3. **Sync scope follows the account.**
   - **No linked account:** everything syncs.
   - **YT Zero linked:** only instances sync. The library is still the account's (ADR 0002).
   - **Scope changes:** the saved engine state records its scope. When the scope changes, sync starts over: everything is fetched and uploaded again, which last-writer-wins makes idempotent. This replaces "sync stops when an account is linked".
4. **Duplicates collapse by URL.** Two devices can add the same instance before they sync. The list shows the first one added, and adding a URL that's already there is refused ("already in your list").
5. **The app observes the instance table.** When the list changes (from sync, or from this device), it rebuilds sources and refreshes, so the TV picks up the phone's instances without a relaunch.

## Consequences

- Nothing changes for builds without `CLOUDKIT_CONTAINER`: sync stays off, and instances stay local.
- **Device check for the owner:** with iCloud configured, add a Piped and a YT Zero instance on the iPhone. The Apple TV signed into the same Apple Account should list both within a minute of opening the app and play from YT Zero without pairing. Removing one on the iPhone should remove it on the TV.
