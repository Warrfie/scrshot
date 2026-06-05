# GitHub Signed and Notarized macOS Builds

The repository does not store Apple Team IDs, certificates, passwords, or provisioning files.
Signed and notarized artifacts are created in GitHub Actions from repository secrets.

## Required GitHub Secrets

Create these secrets in `Settings > Secrets and variables > Actions > Repository secrets`.

| Secret | Notes |
| --- | --- |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID. |
| `MACOS_CODE_SIGN_IDENTITY` | Usually `Developer ID Application: Your Name (TEAMID)` for public downloads. |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` signing certificate. |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `ASC_API_KEY_ID` | App Store Connect API key ID. |
| `ASC_API_ISSUER_ID` | App Store Connect issuer ID. |
| `ASC_API_KEY_P8_BASE64` | Base64-encoded App Store Connect `.p8` API key. |
| `KEYCHAIN_PASSWORD` | Optional. If omitted, CI generates a temporary password. |

## Apple Developer Certificate

Create or use an existing `Developer ID Application` certificate in Apple Developer account.

Export the certificate with its private key from Keychain Access as `.p12`, then encode it:

```bash
base64 -i certificate.p12 | pbcopy
```

Paste the copied value into `MACOS_CERTIFICATE_P12_BASE64`.

Use the export password as `MACOS_CERTIFICATE_PASSWORD`.

## App Store Connect API Key

Create an App Store Connect API key with access to notarization:

1. Open App Store Connect.
2. Go to `Users and Access`.
3. Open the `Integrations` tab.
4. Create an API key.
5. Download the `.p8` file once.
6. Copy `Key ID` into `ASC_API_KEY_ID`.
7. Copy `Issuer ID` into `ASC_API_ISSUER_ID`.
8. Encode the `.p8` file:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste the copied value into `ASC_API_KEY_P8_BASE64`.

## GitHub Actions Release Flow

The `Release Artifacts` workflow runs automatically for tags matching `v*`.

It can also be started manually from `Actions > Release Artifacts > Run workflow`.
Use `signed = true` for signed, notarized, and stapled artifacts.

The signed flow performs:

1. Import Developer ID certificate into a temporary keychain.
2. Build the Release app with Developer ID signing.
3. Create a DMG.
4. Sign the DMG.
5. Submit the DMG to Apple notarization with `notarytool`.
6. Staple the notarization ticket to the DMG.
7. Validate the stapled ticket.
8. Run Gatekeeper assessment with `spctl`.
9. Upload the DMG and SHA256 file as GitHub Actions artifacts.

## Local Signed Build

Copy the example config:

```bash
cp Config/Signing.xcconfig.example Config/Signing.local.xcconfig
```

Fill in local values, then build with:

```bash
xcodebuild -project scrshot.xcodeproj -scheme scrshot -configuration Release -xcconfig Config/Signing.local.xcconfig build
```

`Config/Signing.local.xcconfig` is ignored by git.
