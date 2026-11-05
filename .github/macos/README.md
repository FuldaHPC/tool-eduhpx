# Signing and notarizing the macOS app (optional)

Without a certificate from Apple, macOS blocks the downloaded app at the first start (Gatekeeper). The workflow
`macos.yaml` then only signs "ad hoc", which keeps the app from being reported as damaged on Apple silicon; users have
to allow it once (see the README of the repository).

With an **Apple Developer account** (Apple Developer Program, about 99 US$ per year; ask your IT if the university
already has one) the app opens with a double click. Steps once:

1. In the Apple Developer portal create a certificate "Developer ID Application" and export it from the keychain as
   a `.p12` file with a password.
2. Create an app-specific password for the Apple ID at appleid.apple.com (used by `notarytool`).
3. In the GitHub repository: Settings > Secrets and variables > Actions > New repository secret, with these names:

| Secret | Content |
|---|---|
| `MACOS_CERT_P12` | the `.p12` file as base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the password of the `.p12` file |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `MACOS_NOTARY_APPLE_ID` | the Apple ID (e-mail) |
| `MACOS_NOTARY_PASSWORD` | the app-specific password |
| `MACOS_NOTARY_TEAM_ID` | the 10-character team id |

As soon as `MACOS_CERT_P12` exists, `macos.yaml` signs with the hardened runtime
(`EduHPX.entitlements`), notarizes the app with Apple and staples the ticket. Without the secrets nothing changes.
**These steps could not be tested yet** (no account at hand): the first run with secrets may need small fixes.
