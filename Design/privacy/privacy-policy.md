# SwiftPDF Signer — Privacy Policy

**Effective date:** May 12, 2026

## Summary

SwiftPDF Signer is an iOS app that lets you fill in and sign PDF forms on your iPad and upload the signed copies to your own Dropbox account. We don't collect any personal data, we don't track you, we run no servers, and we don't have access to the forms you sign. Your data stays between your device and your own Dropbox account. The public source the app is built from is available here: https://github.com/JoshuaCalhoon/swiftpdf-signer. It’s also available as the SourceRepository string in the App Bundle. 

## What data the app collects

**None, directly.** SwiftPDF Signer is a client-only app. Bar-All IT operates no servers in connection with this app, stores no user data on infrastructure we control, and integrates no analytics, crash reporters, marketing pixels, or advertising SDKs.

The only data the app stores locally on your device:

- Brand color and header defaults (Your Company, Your Location, Your Department) you set in Settings, stored in iOS UserDefaults on your device only
- An optional company logo you set in Settings, stored as a JPEG file in the app's Documents folder on your device only and marked excluded from iOS and iCloud backups so the bytes are not silently exfiltrated through device backup
- A Dropbox OAuth refresh token, stored in the iOS Keychain on your device only
- A flag indicating whether the first-run sample template has been seeded

This data never leaves your device except via the Dropbox integration described below.

## How the app uses Dropbox

To upload signed PDFs to your Dropbox, the app integrates the official Dropbox SDK (SwiftyDropbox version 10.2.4). When you tap "Connect Dropbox":

- The Dropbox SDK opens a Dropbox-hosted OAuth screen in an in-app browser. You sign in directly with Dropbox; we never see your Dropbox username or password.
- On success, Dropbox returns an OAuth refresh token that is stored on your device in the iOS Keychain.
- The app reads and writes files within a single dedicated folder in your Dropbox: `/Apps/SwiftPDF Signer/`. The app cannot access any other folder.
- Signed PDFs are uploaded directly from your device to your Dropbox account. They do not pass through any server we operate.

## What the Dropbox SDK processes

The following data types are transmitted to Dropbox in connection with delivering uploads to your account. The Dropbox SDK declares all but **Name** in its Apple privacy manifest; we surface them all here for transparency:

- **Name** — the signer's name appears in the body of the PDF you sign and in the upload filename (`{Form} - {Signer} [{Date}].pdf`), both of which are delivered to your Dropbox account
- **Other user content** — the PDF files you sign and upload
- **Photos or videos** — the Dropbox API category that covers uploaded files; the app itself uploads only PDFs and .json template files.
- **Email address, User ID, audio data, search history** — supported by the broader Dropbox API but never fetched or exercised by this app
- **Product interaction, other diagnostic data** — operational metadata the Dropbox SDK may send to Dropbox to deliver the upload service

None of these are used for cross-app or cross-site tracking. All are linked to your Dropbox account because that is where your data is delivered. All are processed solely to enable the app's functionality.

## Third-party services

The app integrates with Dropbox (Dropbox, Inc.). Dropbox's own privacy practices govern how they handle your account data and uploaded files. See Dropbox's privacy policy: <https://www.dropbox.com/privacy>

We do not integrate any other third-party services, SDKs, or analytics providers.

## Data retention

Because we don't store your data on any infrastructure we operate, there is nothing for us to retain. Files you upload remain in your Dropbox account until you delete them. The OAuth refresh token remains in your device's Keychain until you tap "Disconnect Dropbox" from the template library's "…" menu, at which point it is removed.

## Your rights

Because your data is held in your own Dropbox account or on your own device, you have direct control over it at all times. You can:

- View, edit, or delete any signed PDF directly through Dropbox.
- Revoke the app's access to Dropbox at any time, either from within SwiftPDF Signer (template library → "…" menu → Disconnect Dropbox) or from your Dropbox account's connected-apps page at <https://www.dropbox.com/account/connected_apps>.
- Delete the app from your device to remove all locally stored settings and the OAuth refresh token.
- For data Dropbox handles on your behalf, exercise your rights under their privacy policy — including any GDPR, CCPA, or other applicable rights — directly with Dropbox.

## Children's privacy

SwiftPDF Signer is not directed at children under 13, and we do not knowingly collect any data from children. Because the app does not collect data from anyone, no special collection occurs regarding children.

## Changes to this policy

If we change this policy, the new effective date will appear at the top of this page. Material changes will also be summarized in the app's release notes on the App Store.

## Contact

Questions about this privacy policy:

**josh@bar-all.com**

---

*SwiftPDF Signer is published by Bar-All IT. Source available on GitHub at: https://github.com/JoshuaCalhoon/swiftpdf-signer*
