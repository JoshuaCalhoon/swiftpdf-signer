# Security Policy

## Reporting a vulnerability

If you find a security issue in SwiftPDF Signer, please report it privately rather than opening a public issue or pull request.

**Email:** josh@bar-all.com

Please include:

- A description of the issue and its potential impact
- Steps to reproduce, or a minimal proof of concept
- The affected version — visible in **Settings → About** within the app, or by the commit SHA in this repository

I'll acknowledge receipt within a few days and follow up with a fix timeline.

## Scope

SwiftPDF Signer is a small, client-only iOS app. Security issues most relevant to this scope:

- Bypasses of the manager-authentication gate (`ManagerGate`) that protect administrative actions during customer signing
- Mishandling of the Dropbox OAuth refresh token (which is stored in the iOS Keychain)
- Filename or path-handling bugs that could cause files to be written outside the app's scoped Dropbox folder
- Crashes or undefined behavior triggered by malformed PDF templates or user input
- Memory or information leaks involving signature data, signer names, or template content

Out of scope:

- The Dropbox service itself — report those to Dropbox via their security program
- Apple platform issues — report to <product-security@apple.com>
- General SwiftyDropbox issues — report at <https://github.com/dropbox/SwiftyDropbox/security>

## No bounty program

This is a small project published in good faith for transparency. There is no monetary bug bounty. If you'd like acknowledgment in the changelog or App Store release notes for a responsible disclosure, just say so when you report.

## Supported versions

Security fixes are released for the most recent App Store version. Older versions are not back-patched.
