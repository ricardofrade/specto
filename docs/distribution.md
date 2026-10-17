# Distribution

How builds reach people, and what happens if App Review says no.

## TestFlight (primary)

1. **Bundle IDs and team:** put them in `App/Local.xcconfig` (not committed), which `App/Signing.xcconfig` includes: `SPECTO_BUNDLE_PREFIX = com.yourname` and `DEVELOPMENT_TEAM = <Team ID>`. Every target's bundle ID and the App Group (`group.<prefix>.specto`) follow the prefix. The committed default, `dev.placeholder`, is a placeholder; the signpost subsystem string doesn't need to change.
2. **Gate:** tag `v<version>`, which runs `release.yml`: the full CI plus the performance gates enforced on a device.
3. **Upload:** archive and upload (Xcode Organizer, or `xcodebuild -exportArchive` with the App Store Connect key).
4. **Testers:**
   - **Internal:** testing starts as soon as the build is processed.
   - **Public link:** goes through Beta App Review. Use the notes in `docs/app-review.md`.

## If App Review rejects the App Store submission

The likely grounds are 5.2.3 (third-party content) and 4.2 (minimum functionality without a configured server). Respond in this order:

1. **Clarify and resubmit:**
   - **Positioning:** the app ships no content or server; it is a client for servers the user runs.
   - **Branding:** no YouTube branding anywhere.
   - **Downloads:** no downloads in the App Store build.
   - **Reviewer access:** the demo instance is in the notes.
   - **Explanation:** offer a call with App Review to walk through it.
2. **TestFlight:** builds expire after 90 days, and external testing passes Beta App Review, which applies the same guidelines. So TestFlight is a route only if the rejection was about App Store presentation, not content. Internal testers (up to 100 App Store Connect users) skip review.
3. **EU alternative marketplace** (iOS and iPadOS, Digital Markets Act):
   - **Process:** notarisation instead of App Review. Notarisation still checks security and basic functionality, not content rules.
   - **Requirements:** an alternative-distribution entitlement and a marketplace that lists the app. Check fees and terms at the time.
   - **Reach:** EU users only.
4. **Direct install on the owner's devices:** Xcode or `devicectl` with a development or ad-hoc profile. Always available, but personal use only.

## Offline downloads (M6) and the App Store

Guideline 5.2.3 forbids saving media from third-party sources without authorisation, and TestFlight's Beta App Review applies the same rule. M6's offline listening therefore ships behind a build setting (`OFFLINE_DOWNLOADS`):

- **Off:** App Store and TestFlight builds.
- **On:** direct installs and an EU alternative marketplace, where App Store content rules don't apply. Notarisation still does.

## On your own devices with a free Apple ID

Xcode → Settings → Accounts → add your Apple ID: it makes a free Personal Team. Set that team and a bundle prefix nobody else uses in `App/Local.xcconfig`, turn on Developer Mode on the device (Settings → Privacy & Security), and build to it from Xcode. Free teams:

- **Builds expire after 7 days:** install again from Xcode.
- **No iCloud sync and no CarPlay:** those capabilities need the paid program. The iPhone app's device builds already leave its entitlements out (CarPlay, App Group).
- **Limits:** 3 such apps per device, 10 new App IDs a week.
