# 0011 — Apple TV profiles

Date: 2026-10-17. Status: accepted.

## Decision

The Apple TV app and its Top Shelf extension carry `com.apple.developer.user-management = [runs-as-current-user]`. tvOS then runs the app as the current Apple TV user. Each person has their own:

- **Container:** the database cache (`Caches/Library/app.sqlite`, ADR 0004), settings and App Group snapshot.
- **iCloud account:** CloudKit sync, so their own instances, subscriptions, history and saved playlists (ADRs 0004, 0006, 0008).
- **Keychain:** YT Zero tokens, which arrive with their instances through their own iCloud (ADR 0006).

The app itself needs no profile code: everything that differs per person already comes from the container, iCloud or the keychain. Switching users relaunches the app as the new user.

`runs-as-current-user-with-user-independent-keychain` was not chosen. It would share YT Zero tokens across people, so one person's account would answer for another.

## Consequences

- **Release setup** (parked): the App ID needs the User Management capability before the entitlement can be signed for a device.
- **Device check for the owner:** add a second user in Apple TV Settings → Users and Accounts, then switch to them. Specto should open with that person's instances and subscriptions (empty without iCloud setup), and Top Shelf should show their Continue Watching. Switching back restores the first person's.
