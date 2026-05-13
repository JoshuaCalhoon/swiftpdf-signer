# SwiftPDF Signer

A native iOS app for filling and signing PDF forms on iPad and iPhone, then uploading the signed copies to your own Dropbox account.

Hand a customer the iPad, they sign with finger or Pencil, the app flattens to PDF, names it deterministically (`{FormName} - {SignerName} [{Date}].pdf`), and uploads to a dedicated Dropbox app folder.

## Why this repository is public

SwiftPDF Signer's [privacy policy](./Design/privacy-policy.md) makes specific claims — no data collection, no analytics, no developer access to anything you sign. Publishing the source is how those claims become verifiable. Anyone can:

1. Read the code to confirm what the app actually does
2. Clone, build, and run a version themselves
3. Compare their build's behavior against the App Store binary they installed

To make verification concrete, each build embeds the commit SHA visible in **Settings → About**. Tap it to open this repository at the exact revision the installed binary was built from.

## What this is, technically

- Native SwiftUI; iOS 18.6 minimum; iPhone + iPad
- [SwiftyDropbox](https://github.com/dropbox/SwiftyDropbox) for OAuth (PKCE) + file upload to a Dropbox app folder
- PDF rendering via `UIGraphicsPDFRenderer` + `NSAttributedString` (no PDFKit dependency for the output path)
- Signature capture via PencilKit
- Manager-gated administrative actions via `LocalAuthentication` (Face ID / passcode)
- No backend, no analytics SDKs, no advertising SDKs, no crash reporters

## Building from source

You need:

- macOS with Xcode 26+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A Dropbox app registered at <https://www.dropbox.com/developers/apps> — scope: **App folder**; permissions: `files.content.read` + `files.content.write`

Steps:

```bash
git clone https://github.com/JoshuaCalhoon/swiftpdf-signer.git
cd swiftpdf-signer

# Fill in your own Dropbox app key + Apple Developer Team ID
cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
$EDITOR Configuration/Local.xcconfig

# Regenerate the Xcode project from project.yml
xcodegen generate

# Build (or open SwiftPDF.xcodeproj in Xcode)
xcodebuild -project SwiftPDF.xcodeproj -scheme "SwiftPDF Signer" \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The Dropbox app key is a public OAuth client identifier (PKCE makes the key alone insufficient to impersonate). `DEVELOPMENT_TEAM` is used for code signing only and never leaves your machine.

## Mirror status

This repository is a public snapshot of an internal Gitea repository where development happens. Each public revision represents a release-ready state at the time of publication. Issues are welcome; pull requests will be evaluated case-by-case but may not be the fastest path to changes — feel free to fork.

## License

[MIT](./LICENSE) — see the LICENSE file for the full text. Use, modify, fork, and redistribute freely.

## Author

Directed by [Joshua Calhoon](https://github.com/JoshuaCalhoon), IT Administrator at [Bar-All](https://barallinc.com). Code written by Claude Code and/or local LLM models.

## Security

If you find a security issue, see [SECURITY.md](./SECURITY.md) — please report privately rather than opening a public issue.
