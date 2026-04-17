# macOS Distribution

Use this flow when you want to ship Codex Audio Monitor as a normal downloadable Mac app.

## Recommended format

Ship a notarized `.dmg` with a drag-and-drop install flow:

1. User downloads `CodexAudioMonitor.dmg`
2. Opens the disk image
3. Drags `CodexAudioMonitor.app` into `Applications`
4. Launches the installed app from `/Applications`

This is the cleanest path for a menu bar app and gives the right Gatekeeper/TCC behavior.

## Prerequisites

- Apple Developer account
- `Developer ID Application` certificate in local keychain
- `asc` configured via `asc auth login`
- Local Xcode build succeeds

Check prerequisites:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
asc auth status
```

## Build a signed + notarized release

```bash
./scripts/release-macos.sh --team-id YOUR_TEAM_ID
```

Optional:

```bash
./scripts/release-macos.sh --team-id YOUR_TEAM_ID --profile YOUR_ASC_PROFILE
./scripts/release-macos.sh --team-id YOUR_TEAM_ID --skip-notarize
./scripts/release-macos.sh --team-id YOUR_TEAM_ID --skip-dmg
```

Artifacts are written to `dist/release/`.

Expected outputs:

- `dist/release/export/CodexAudioMonitor.app`
- `dist/release/CodexAudioMonitor.zip`
- `dist/release/CodexAudioMonitor.zip.sha256`
- `dist/release/CodexAudioMonitor.dmg`
- `dist/release/CodexAudioMonitor.dmg.sha256`

## Why this matters

Running from Xcode is fine for development, but it is not the final distribution model:

- app lives under `DerivedData`
- TCC/privacy behavior is less representative
- third parties cannot install it cleanly

The release flow above produces a real app bundle and installer artifact suitable for distribution outside the App Store.

## Notes

- `Mute/Unmute` behavior should be validated again on the installed app, not only in the debug build.
- App Gain permission prompts are expected to behave more predictably from an installed build in `/Applications`.
- If you later want automatic updates, add Sparkle on top of this DMG-based release flow.
