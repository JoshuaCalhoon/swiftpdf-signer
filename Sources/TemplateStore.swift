import Foundation
import Observation

/// Owns the list of templates shown in `LibraryView`.
/// Merges the bundled built-ins (e.g. `FormTemplate.generalSafetyV1`) with
/// user-authored templates synced from `/Apps/SwiftPDF/Templates/` in Dropbox.
///
/// Bundled templates are always visible and aren't deletable.
/// User templates have `editable == true` and are written as one JSON file per
/// template (`{uuid}.json`), with `mode: .overwrite` so an edit-and-save round-trip
/// updates in place rather than autorenaming.
@MainActor
@Observable
final class TemplateStore {
    private(set) var templates: [FormTemplate]
    private(set) var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private let dropbox: DropboxService
    private let bundled: [FormTemplate] = [.generalSafetyV1]

    init(dropbox: DropboxService) {
        self.dropbox = dropbox
        // Bundled templates are visible immediately so the UI has something to
        // render even before the first sync completes (or if it fails).
        self.templates = bundled
    }

    /// Pulls the latest template set from Dropbox, decodes each, and rebuilds
    /// `templates` as [bundled, ...synced sorted-by-name]. A failure leaves the
    /// list intact at its last good state and surfaces a message via `loadState`.
    ///
    /// Any synced template whose `id` matches a bundled sentinel (see
    /// `FormTemplate.BundledID`) is dropped — the in-app bundled copy is the
    /// source of truth and a file on Dropbox can't override it.
    func refresh() async {
        loadState = .loading
        do {
            let refs = try await dropbox.listTemplates()
            var loaded: [FormTemplate] = []
            for ref in refs {
                do {
                    let data = try await dropbox.downloadTemplate(at: ref.path)
                    let decoded = try Self.decoder.decode(FormTemplate.self, from: data)
                    if FormTemplate.BundledID.all.contains(decoded.id) {
                        NSLog("[TemplateStore] rejected bundled-id impersonation: \(ref.name)")
                        continue
                    }
                    loaded.append(decoded)
                } catch {
                    // One corrupt template shouldn't block the others.
                    NSLog("[TemplateStore] skipped \(ref.name): \(error)")
                }
            }
            templates = bundled + loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadState = .loaded
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }

    /// Saves `template` to Dropbox and updates the local list. Used for both
    /// create and edit — `mode: .overwrite` handles both paths.
    func save(_ template: FormTemplate) async throws {
        guard template.editable else {
            throw StoreError.notEditable
        }
        let data = try Self.encoder.encode(template)
        _ = try await dropbox.saveTemplate(data, filename: Self.filename(for: template))
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
        } else {
            templates.append(template)
            templates = bundled + templates.dropFirst(bundled.count)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Deletes a user-authored template from Dropbox and the local list.
    /// Bundled templates are silently no-ops — the caller should hide the affordance.
    func delete(_ template: FormTemplate) async throws {
        guard template.editable else { return }
        let path = "\(DropboxConfig.templatesFolder)/\(Self.filename(for: template))"
        try await dropbox.deleteTemplate(at: path)
        templates.removeAll { $0.id == template.id }
    }

    enum StoreError: LocalizedError {
        case notEditable
        var errorDescription: String? {
            switch self {
            case .notEditable: return "Bundled templates can't be edited."
            }
        }
    }

    private static func filename(for template: FormTemplate) -> String {
        "\(template.id.uuidString).json"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
