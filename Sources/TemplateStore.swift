import Foundation
import Observation
import os

/// Owns the list of templates shown in `LibraryView`. All templates are
/// Dropbox-synced JSON files at `/Apps/{app}/Templates/{uuid}.json`; a sample
/// template is seeded into Dropbox on the user's first launch (when the
/// folder is empty) so the library has something to demonstrate the format.
/// After seeding, the sample is just a regular template — fully editable,
/// duplicatable, and deletable.
@MainActor
@Observable
final class TemplateStore {
    private(set) var templates: [FormTemplate]
    private(set) var loadState: LoadState = .idle
    /// Number of templates the most recent `refresh()` had to skip due to
    /// corrupt JSON. Surfaced in `LibraryView`'s footer so the manager isn't
    /// left guessing about a quietly-shorter list. Reset to zero at the top
    /// of each `refresh()`.
    private(set) var lastRefreshSkipCount: Int = 0
    /// True once the in-memory demo library has been seeded with the sample.
    /// Guards `refresh()` against re-seeding on every pull-to-refresh — without
    /// this flag a reviewer who deletes the sample, then pulls down to
    /// refresh, would see it reappear with a fresh UUID.
    private var hasSeededDemo = false

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
    private let defaults: UserDefaults

    init(dropbox: DropboxService, defaults: UserDefaults = .standard) {
        self.dropbox = dropbox
        self.defaults = defaults
        self.templates = []
    }

    /// Pulls the latest template set from Dropbox, decodes each, and rebuilds
    /// `templates` sorted by name. A failure leaves the list intact at its
    /// last good state and surfaces a message via `loadState`.
    ///
    /// First-run seeding: when the user has zero templates AND we haven't
    /// seeded before on this iPad, write the sample template to Dropbox so
    /// the library has something to show on first launch. The
    /// `hasSeededSample` flag is local to the device, so a second iPad
    /// joining an existing account won't re-seed.
    func refresh() async {
        // Demo session never touches Dropbox. First refresh seeds the
        // sample template; subsequent refreshes leave the in-memory list
        // alone so a reviewer's edits / deletes / new templates persist
        // across pull-to-refresh.
        if dropbox.authState == .demo {
            if !hasSeededDemo {
                templates = [FormTemplate.makeFreshSample()]
                hasSeededDemo = true
            }
            lastRefreshSkipCount = 0
            loadState = .loaded
            return
        }

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
                    loaded.append(decoded)
                case .failure(let error):
                    // Error body is `.private` because `DecodingError.dataCorrupted`
                    // can quote source fragments — keep it out of Console logs.
                    Self.logger.warning("Skipped corrupt template \(ref.name, privacy: .public): \(error.localizedDescription, privacy: .private)")
                    skipped += 1
                }
            }

            // First-run seed. If the user's Dropbox templates folder is
            // genuinely empty (zero entries) and we haven't seeded yet on
            // this iPad, upload the sample. Keyed on `refs.isEmpty` rather
            // than `loaded.isEmpty` so an account whose existing templates
            // all fail to decode (corrupt JSON, partial sync) doesn't get
            // a "Warehouse Waiver" appearing next to their failing files
            // — they see the skip-count warning in the library footer
            // instead. A seed failure is logged but doesn't fail the whole
            // refresh — the user can still create templates manually.
            if refs.isEmpty && !defaults.bool(forKey: Self.hasSeededSampleKey) {
                let sample = FormTemplate.makeFreshSample()
                do {
                    let data = try Self.makeEncoder().encode(sample)
                    _ = try await dropbox.saveTemplate(data, filename: Self.filename(for: sample))
                    defaults.set(true, forKey: Self.hasSeededSampleKey)
                    loaded.append(sample)
                } catch {
                    Self.logger.warning("Initial sample seed failed: \(error.localizedDescription, privacy: .private)")
                }
            }

            templates = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    /// patching by index so the result is correct regardless of what
    /// `refresh` may have done while we waited.
    func save(_ template: FormTemplate) async throws {
        guard template.editable else {
            throw StoreError.notEditable
        }
        // Demo session: in-memory write only, no Dropbox round-trip.
        if dropbox.authState == .demo {
            var updated = templates.filter { $0.id != template.id }
            updated.append(template)
            templates = updated.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return
        }
        let data = try Self.makeEncoder().encode(template)
        _ = try await dropbox.saveTemplate(data, filename: Self.filename(for: template))
        var updated = templates.filter { $0.id != template.id }
        updated.append(template)
        templates = updated.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Deletes a template from Dropbox and the local list. Non-editable
    /// templates are silently no-ops (no current path produces one, but the
    /// guard remains in case future code reintroduces bundled-immutable
    /// content).
    func delete(_ template: FormTemplate) async throws {
        guard template.editable else { return }
        // Demo session: in-memory delete only, no Dropbox round-trip.
        if dropbox.authState == .demo {
            templates.removeAll { $0.id == template.id }
            return
        }
        let path = "\(DropboxConfig.templatesFolder)/\(Self.filename(for: template))"
        try await dropbox.deleteTemplate(at: path)
        templates.removeAll { $0.id == template.id }
    }

    /// Clears the first-run seed flag so the next `refresh()` on an empty
    /// Dropbox folder will re-seed the sample. Called when the user
    /// disconnects Dropbox (a deliberate "start over" gesture) — without
    /// this, reconnecting to a fresh / wiped Dropbox account leaves the
    /// library empty because the flag thinks we've already seeded once.
    func resetSeedFlag() {
        defaults.removeObject(forKey: Self.hasSeededSampleKey)
    }

    /// Drops the in-memory demo library so the next refresh — which will be
    /// against real Dropbox by the time it runs — starts from a clean slate
    /// instead of inheriting the reviewer's sample edits. Called by
    /// LibraryView when leaving demo to connect a real account.
    func resetForDemoExit() {
        templates = []
        loadState = .idle
        hasSeededDemo = false
        lastRefreshSkipCount = 0
    }

    enum StoreError: LocalizedError {
        case notEditable
        var errorDescription: String? {
            switch self {
            case .notEditable: return "This template can't be edited."
            }
        }
    }

    private static let hasSeededSampleKey = "hasSeededSample"

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
