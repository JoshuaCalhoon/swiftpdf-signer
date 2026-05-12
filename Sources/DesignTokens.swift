import SwiftUI

extension Color {
    /// App accent color for primary actions, focus rings, and brand surfaces.
    /// Phase 2 wires this to a per-install setting persisted in `AppSettings`;
    /// for now it's a static default.
    static let brandAccent: Color = .orange
}
