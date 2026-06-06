# GitHub Signed and Notarized macOS Builds

The repository does not store Apple Team IDs, certificates, passwords, or provisioning files.
Signed and notarized artifacts are created in GitHub Actions from repository secrets.

## Required GitHub Secrets

Create these secrets in `Settings > Secrets and variables > Actions > Repository secrets`.

| Secret | Notes |
| --- | --- |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID. |
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

The workflow resolves the `Developer ID Application` identity automatically from the imported temporary keychain, so no separate signing identity secret is required.

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
2. Resolve the Developer ID signing identity from that keychain.
3. Build the Release app with Developer ID signing and a secure timestamp.
4. Create a DMG.
5. Sign the DMG with a secure timestamp.
6. Submit the DMG to Apple notarization with `notarytool`.
7. Staple the notarization ticket to the DMG.
8. Validate the stapled ticket.
9. Run `spctl` as a diagnostic-only Gatekeeper assessment.
10. Upload the DMG and SHA256 file as GitHub Actions artifacts for CI/debug access.
11. For tag builds, create or update the matching GitHub Release and attach the DMG and SHA256 file as public release assets.

`spctl` can report `source=Insufficient Context` on GitHub-hosted runners even after successful notarization and stapling. The release gate is Apple notarization plus `stapler validate`; `spctl` is logged for diagnostics and does not fail the workflow when those checks succeed.

## Public Downloads

For tags matching `v*`, the workflow publishes these files to the matching GitHub Release:

- `scrshot-<tag>.dmg`
- `scrshot-<tag>.sha256`

Use GitHub Releases for user-facing downloads:

```text
https://github.com/Warrfie/scrshot/releases
```

GitHub Actions artifacts are temporary CI/debug artifacts with limited retention. They are not intended as the primary distribution channel for users.

## Manual Builds

Manual workflow runs are useful for testing the signed pipeline before creating a release tag:

1. Open `Actions > Release Artifacts > Run workflow`.
2. Set `signed = true`.
3. Download the resulting workflow artifact from the run page.

Manual runs do not create a GitHub Release asset unless the workflow is running for a `v*` tag.

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
