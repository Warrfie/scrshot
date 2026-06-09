# Release Checklist

## Before Every Release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, or pass them into the release scripts.
2. Run tests:

   ```bash
   xcodebuild test -project scrshot.xcodeproj -scheme scrshot -derivedDataPath .deriveddata-release-check CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" COMPILER_INDEX_STORE_ENABLE=NO -destination 'platform=macOS'
   ```

3. Verify the app launches from a clean install and appears in the menu bar.
4. Verify screenshot capture with Screen Recording permission granted.
5. Verify the first-save folder permission flow.
6. Verify recording start and stop on macOS 15 or later.
7. Verify microphone recording mode asks for Microphone permission only when selected.
8. Verify About includes the privacy policy link.

## Developer ID / Public DMG

Use this path for GitHub Releases and direct downloads:

```bash
SIGNING_ALLOWED=YES NOTARIZATION_ALLOWED=YES ./scripts/build-dmg.sh
```

Required secrets or local environment:

- Developer ID Application certificate
- Apple Developer Team ID
- App Store Connect API key with notarization access

The output DMG should be signed, notarized, stapled, and accompanied by a SHA-256 checksum.

## Mac App Store / TestFlight

Use this path for App Store Connect:

```bash
DEVELOPMENT_TEAM_VALUE=<APPLE_TEAM_ID> ./scripts/build-appstore.sh
```

If the machine needs Xcode to create or download signing assets automatically, use:

```bash
DEVELOPMENT_TEAM_VALUE=<APPLE_TEAM_ID> APPSTORE_ALLOW_PROVISIONING_UPDATES=YES ./scripts/build-appstore.sh
```

For CI-style authentication, also provide:

- `ASC_API_KEY_PATH`
- `ASC_API_KEY_ID`
- `ASC_API_ISSUER_ID`

Prerequisites:

- App Store Connect app record for bundle ID `io.github.Warrfie.scrshot`
- Apple Distribution certificate
- Mac App Store Connect provisioning profile, or Xcode automatic signing access
- App Store Connect metadata, screenshots, privacy policy URL, and review notes

After export, upload the generated package with Xcode Organizer or Transporter.

## App Store Connect Metadata

Minimum metadata to prepare:

- App name: `scrshot`
- Category: Utilities
- Privacy policy URL: `https://github.com/Warrfie/scrshot/blob/main/docs/PRIVACY.md`
- Review notes: use `docs/APP_REVIEW_NOTES.md`
- Screenshots showing the menu bar, Preferences, editor, and recording menu state

## Privacy Manifest

The app bundle includes `PrivacyInfo.xcprivacy` because scrshot uses `UserDefaults` for app-only preferences. The manifest declares:

- `NSPrivacyAccessedAPICategoryUserDefaults`
- reason `CA92.1`
- no tracking
- no collected data
