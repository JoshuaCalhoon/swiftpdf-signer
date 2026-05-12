import SwiftUI

/// Manager-facing settings sheet. Entry point is gated by `ManagerGate` from
/// `LibraryView`'s toolbar, so a customer signing on a shared iPad can't
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
        // Local @Bindable shadow so we can derive bindings ($settings.foo)
        // from an Environment-injected @Observable. The shadow is scoped to
        // this view's body — the actual state lives in the env-injected
        // instance.
        @Bindable var settings = settings

        NavigationStack {
            Form {
                preview

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
                    TextField("Company", text: $settings.companyName)
                        .textInputAutocapitalization(.words)
                    TextField("Location", text: $settings.companyLocation)
                        .textInputAutocapitalization(.words)
                    TextField("Department", text: $settings.companyDepartment)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Form Header Defaults")
                } footer: {
                    Text("Used for the company / location / department fields at the top of every newly-created template. Leave blank to keep the generic placeholders.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset brand color") {
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

    /// Inline sample of the brand color applied to a title and a button, so
    /// the manager can see the effect of the picker without dismissing the
    /// sheet to check.
    private var preview: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample Form Title")
                    .font(.title2.bold())
                    .foregroundStyle(settings.brandColor)
                Button {} label: {
                    Text("Sample Button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.brandColor)
                .controlSize(.large)
                .allowsHitTesting(false)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Preview")
        }
    }
}
