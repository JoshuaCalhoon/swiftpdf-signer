import Foundation
import Observation
import os

/// Owns the list of templates shown in `LibraryView`.
/// Merges the bundled built-ins (e.g. `FormTemplate.sampleAcknowledgmentV1`) with
/// user-authored templates synced from the app's `/Templates/` folder in Dropbox.
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
    /// Number of templates the most recent `refresh()` had to skip — either
    /// corrupt JSON or bundled-id impersonation attempts. Surfaced in
    /// `LibraryView`'s footer so the manager isn't left guessing about a
    /// quietly-shorter list. Reset to zero at the top of each `refresh()`.
    private(set) var lastRefreshSkipCount: Int = 0

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "swiftpdf",
        category: "TemplateStore"
    )

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private let dropbox: DropboxService
    private let bundled: [FormTemplate] = [.sampleAcknowledgmentV1]

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
        var skipped = 0
        do {
            let refs = try await dropbox.listTemplates()

            // Download + decode each template in parallel. At ~1 template
            // today the wall-clock win is invisible; at 10+ it's seconds.
            // Each task captures `ref` so we can blame the right file in the
            // skip log, and returns a Result rather than throwing so a single
            // corrupt JSON doesn't tear down sibling downloads.
            let dropboxRef = self.dropbox
            let outcomes = await withTaskGroup(
                of: (DropboxService.TemplateRef, Result<FormTemplate, Error>).self,
                returning: [(DropboxService.TemplateRef, Result<FormTemplate, Error>)].self
            ) { group in
                for ref in refs {
                    group.addTask {
                        do {
                            let data = try await dropboxRef.downloadTemplate(at: ref.path)
                            let decoded = try Self.makeDecoder().decode(FormTemplate.self, from: data)
                            return (ref, .success(decoded))
                        } catch {
                            return (ref, .failure(error))
                        }
                    }
                }
                var out: [(DropboxService.TemplateRef, Result<FormTemplate, Error>)] = []
                for await item in group { out.append(item) }
                return out
            }

            var loaded: [FormTemplate] = []
            for (ref, result) in outcomes {
                switch result {
                case .success(let decoded):
                    if FormTemplate.BundledID.all.contains(decoded.id) {
                        Self.logger.warning("Rejected bundled-id impersonation in \(ref.name, privacy: .public)")
                        skipped += 1
                        continue
                    }
                    loaded.append(decoded)
                case .failure(let error):
                    // Error body is `.private` because `DecodingError.dataCorrupted`
                    // can quote source fragments — keep it out of Console logs.
                    Self.logger.warning("Skipped corrupt template \(ref.name, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    skipped += 1
                }
            }
            templates = bundled + loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastRefreshSkipCount = skipped
            loadState = .loaded
        } catch {
            lastRefreshSkipCount = skipped
            loadState = .failed(message: error.localizedDescription)
        }
    }

    /// Saves `template` to Dropbox and updates the local list. Used for both
    /// create and edit — `mode: .overwrite` handles both paths.
    ///
    /// After the `await`, the local `templates` array may have been replaced
    /// by a concurrent `refresh()` — both methods are `@MainActor` so they
    /// can't interleave non-await turns, but the suspension point hands the
    /// run-loop back. We reconstruct the array from scratch instead of
    /// patching by index, so the result is correct regardless of what
    /// `refresh` did with the bundled-vs-user partitioning while we waited.
    func save(_ template: FormTemplate) async throws {
        guard template.editable else {
            throw StoreError.notEditable
        }
        let data = try Self.makeEncoder().encode(template)
        _ = try await dropbox.saveTemplate(data, filename: Self.filename(for: template))
        let bundledIDs = Set(bundled.map(\.id))
        var user = templates.filter { !bundledIDs.contains($0.id) && $0.id != template.id }
        user.append(template)
        templates = bundled + user.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

    // Factory methods (not static lets) so they're `nonisolated` and can be
    // called from inside the parallel-download task group without tripping
    // Swift 6's actor isolation check. JSONEncoder/JSONDecoder are reference
    // types and not Sendable — sharing one instance across concurrent tasks
    // is unsafe anyway, so a fresh instance per call is the right model.
    // Allocation is microsecond-cheap.
    nonisolated private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
