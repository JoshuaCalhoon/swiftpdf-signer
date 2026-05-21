import SwiftUI

/// Covers customer-content views with an opaque shield whenever the scene
/// isn't `.active` — for the App Switcher snapshot iOS persists, the
/// multitasking peek, Control Center pulldowns, and the launch-image
/// cache rehydration that briefly flashes prior content on next cold
/// launch. The snapshot iOS captures shows the shield, not the
/// in-progress signer name, signature, or template body.
///
/// Applied at the root of customer-data surfaces (FormView,
/// TemplateEditor) via `.privacyShield()`. Other screens (Library,
/// Connect, Settings) carry no customer-supplied data and skip the
/// shield, so their App Switcher previews stay useful for managers
/// identifying the app among many.
///
/// Visual: brand-colored fill with the app's hero glyph centered.
/// Matches `ConnectDropboxView`'s hero so the App Switcher tile reads
/// as the same app, just locked.
struct PrivacyShieldModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                shield
            }
        }
    }

    private var shield: some View {
        ZStack {
            settings.brandColor
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 88))
                .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Apply on views that show customer-supplied data (signer name,
    /// signature, template body). See `PrivacyShieldModifier`.
    func privacyShield() -> some View {
        modifier(PrivacyShieldModifier())
    }
}
