import SwiftUI

extension Color {
    /// KwikShip brand orange — sourced from KwikShip_Logo.svg on kwikship.com.
    /// Used for primary actions, focus rings, and brand accents.
    /// If KwikShip rebrands, this is the single point of change.
    static let kwikshipOrange = Color(red: 1.0, green: 0x51 / 255.0, blue: 0.0)

    /// Warm dark — secondary brand neutral from the logo SVG.
    static let kwikshipWarmDark = Color(red: 0x3D / 255.0, green: 0x39 / 255.0, blue: 0x35 / 255.0)

    /// Deep brown — used sparingly for high-contrast strokes.
    static let kwikshipDeep = Color(red: 0x30 / 255.0, green: 0x26 / 255.0, blue: 0x1D / 255.0)
}
