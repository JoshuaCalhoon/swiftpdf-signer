import SwiftUI

/// Manager-facing settings sheet. Entry point is gated by `ManagerGate` from
/// `LibraryView`'s toolbar menu, so a customer signing on a shared iPad can't
/// reach this surface without manager authentication.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// `ColorPicker` updates its binding many times per second during slider
    /// drags. Mirror through local state instead of binding straight at
    /// `settings.brandColorHex` — that way UserDefaults sees one write per
    /// settled value, not per drag tick.
    @State private var workingColor: Color = AppSettings.defaultBrandColor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("Accent color", selection: $workingColor, supportsOpacity: false)
                } header: {
                    Text("Brand Color")
                } footer: {
                    Text("Tints primary buttons and indicators in the app, and the document title in signed PDFs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset to default") {
                        settings.resetBrandColor()
                        workingColor = settings.brandColor
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { workingColor = settings.brandColor }
            // `onChange(of: workingColor)` fires every time the picker drag
            // updates the binding. Compare hex strings before writing back
            // so identical-color updates don't trigger a UserDefaults round-trip.
            .onChange(of: workingColor) { _, newValue in
                guard let hex = newValue.toHex(), hex != settings.brandColorHex else {
                    return
                }
                settings.brandColorHex = hex
            }
        }
    }
}
