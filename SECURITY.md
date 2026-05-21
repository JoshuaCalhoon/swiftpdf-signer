# Security Policy

## Reporting a vulnerability

If you find a security issue in SwiftPDF Signer, please report it privately rather than opening a public issue or pull request.

**Email:** josh@bar-all.com

Please include:

- A description of the issue and its potential impact
- Steps to reproduce, or a minimal proof of concept
- The affected version (visible in **Settings → About** within the app, or by the commit SHA in this repository)

I'll acknowledge receipt within a few days and follow up with a fix timeline.

## Scope

SwiftPDF Signer is a small, client-only iOS app. Security issues most relevant to this scope:

- Bypasses of the manager-authentication gate (`ManagerGate`) that protect administrative actions during customer signing
- Mishandling of cloud-provider OAuth credentials (refresh tokens stored in the iOS Keychain). The 1.0 release uses Dropbox; additional providers are planned.
- Filename or path-handling bugs that could cause files to be written outside the app's scoped upload folder
- Crashes or undefined behavior triggered by malformed PDF templates or user input
- Memory or information leaks involving signature data, signer names, or template content

Out of scope:

- The cloud-provider services themselves (today: Dropbox). Report those to the provider's own security program.
- Apple platform issues. Report to <product-security@apple.com>.
- General SwiftyDropbox issues. Report at <https://github.com/dropbox/SwiftyDropbox/security>.

## No bounty program

This is a small project published in good faith for transparency. There is no monetary bug bounty. If you'd like acknowledgment in the changelog or App Store release notes for a responsible disclosure, just say so when you report.

## Supported versions

Security fixes are released for the most recent App Store version. Older versions are not back-patched.

## Known limitations

SDK-level behaviors of the configured cloud provider that we've evaluated and accepted at this release. Tracking them in the open rather than hiding them.

- **Keychain accessibility class.** Today's provider (Dropbox via SwiftyDropbox 10.2.4) stores the OAuth refresh token with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The `ThisDeviceOnly` half blocks iCloud Keychain sync (the token never leaves your iPad). The `AfterFirstUnlock` half means the token is readable while the device is locked but post-first-unlock-since-boot. A stricter `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is not currently configurable via the SDK's public API. The token remains inaccessible to other apps via standard iOS sandboxing in all cases.
- **OAuth CSRF nonce persistence.** The SDK writes a per-attempt random nonce to `UserDefaults` during the OAuth round-trip but doesn't clear it after the redirect validates. The nonce is not identity-bearing (per-attempt random UUID, not linked to account or user), but rides iOS / iCloud backups.

Both items are SDK-side. We've chosen to accept the defaults at this release rather than fork the SDK; future SDK versions or alternative provider conformers may close them.
