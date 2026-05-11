## In progress
- [ ] **User: tap "Connect Dropbox" in the simulator (or on a real iPad)** and complete the OAuth round-trip — confirms the auth gate + URL scheme work end-to-end
- [ ] **User: do one real signed upload** — type a Print Name, sign, tap Done. Verify a file with name `General Safety Rules - {YourName} [{YYYY-MM-DD}].pdf` lands in your Dropbox under `/Apps/SwiftPDF/Signed/`.

## Next
- [ ] Real-world polish after end-to-end testing: success banner auto-dismiss (design.md spec says 2s on success), keyboard avoidance behind the signature canvas, possibly a "Sign Another" interstitial after success
- [ ] Build for a real iPad (USB or wireless deployment via Xcode — need a free Apple Developer team for code signing)
- [ ] v1.1: in-app template editor (deferred — task #13)
- [ ] Revisit Swift 6 mode once SwiftyDropbox catches up (`SwiftyDropbox` 10.2.4 static singleton triggers strict concurrency errors)

## Blocked / questions
- App icon / launch screen branding — defer until v1 ships (cosmetic)
- Should `references/` be cleaned up since the in-app template supersedes the Word-doc pipeline? (Word doc + Resources/General Safety.pdf are no longer used by the app — kept for reference only)
- Multi-page rendering — current renderer assumes content fits one US Letter page. If a future template overruns, FormRenderer needs page-break logic. Not a v1 blocker.

## Done (recent)
- [x] Bootstrap project-memory files
- [x] Pull KwikShip brand colors from `KwikShip_Logo.svg`: #FF5100, #3D3935, #30261D
- [x] Write `design.md` with KwikShip orange accent — approved
- [x] Write `project.yml` for XcodeGen with configFiles + info.properties (URL scheme via xcconfig substitution)
- [x] Architectural pivot: in-app template authoring instead of Word-doc-bundled approach
- [x] Receive Dropbox App Key from user; store in gitignored `Configuration/Local.xcconfig`
- [x] Write v1 sources: `SwiftPDFApp`, `ContentView`, `ConnectDropboxView`, `FormView`, `FormTemplate`, `FormRenderer`, `SignatureCanvas`, `DropboxService`, `DropboxConfig`, `DesignTokens`
- [x] Install iOS 26.4.1 platform package via `xcodebuild -downloadPlatform iOS`
- [x] Switch project to Swift 5 mode (SwiftyDropbox 10.2.4 not Swift-6-strict-ready)
- [x] First successful build for iPad Pro 11 iOS 18.6 simulator — confirmed FormView renders correctly
- [x] Add first-launch Dropbox auth gate (`ConnectDropboxView`), gated by `dropbox.authState` in `ContentView`
- [x] Bump signature canvas to 200pt — fits Pencil/finger signing comfortably
- [x] Confirmed Connect Dropbox screen renders on the simulator
- [x] FormRenderer fix: use `UIGraphicsPDFRendererContext.beginPage()` (replace the `UIGraphicsGetCurrentContext()?.beginPDFPage(nil)` path)
- [x] Error-paths polish pass: cache rendered PDF + Retry button on failure; ellipsis-menu Disconnect Dropbox with confirmation; auth failures during upload (token revoked / refresh fail) clear local auth so ContentView routes back to ConnectDropboxView
