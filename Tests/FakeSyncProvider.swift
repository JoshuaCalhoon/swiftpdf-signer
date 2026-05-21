import Foundation
@testable import SwiftPDF

/// In-memory `SyncProvider` for unit tests. State is `@MainActor`-isolated;
/// tests are `@MainActor` so they read recorded calls and configure stored
/// templates synchronously. Each CRUD method either returns from the
/// in-memory store or throws a preconfigured error so tests can exercise
/// the failure-handling branches in `TemplateStore`.
@MainActor
final class FakeSyncProvider: SyncProvider {

    /// One persisted template the fake provider returns from
    /// `listTemplates` and `downloadTemplate`.
    struct StoredTemplate: Equatable {
        let name: String          // e.g. "<uuid>.json"
        let identifier: String    // e.g. "/templates/<uuid>.json"
        var data: Data            // JSON bytes
    }

    /// Templates the provider currently holds. Mutated by `saveTemplate` /
    /// `deleteTemplate` and inspected by test assertions.
    var stored: [StoredTemplate] = []

    /// If non-nil, the next CRUD call throws this and clears the slot.
    /// One-shot so subsequent calls succeed unless re-armed.
    var nextError: Error?

    // Recorded call sequences — exposed for test assertions.
    private(set) var uploadSignedCalls: [(filename: String, byteCount: Int)] = []
    private(set) var saveTemplateCalls: [(filename: String, byteCount: Int)] = []
    private(set) var deleteTemplateCalls: [String] = []

    // MARK: - SyncProvider

    func uploadSigned(_ pdfData: Data, filename: String) async throws -> UploadResult {
        if let err = nextError { nextError = nil; throw err }
        uploadSignedCalls.append((filename, pdfData.count))
        return UploadResult(path: "/Signed/\(filename)", wasAutorenamed: false)
    }

    func listTemplates() async throws -> [TemplateRef] {
        if let err = nextError { nextError = nil; throw err }
        return stored.map { TemplateRef(name: $0.name, identifier: $0.identifier) }
    }

    func downloadTemplate(at identifier: String) async throws -> Data {
        if let err = nextError { nextError = nil; throw err }
        guard let entry = stored.first(where: { $0.identifier == identifier }) else {
            throw NSError(
                domain: "FakeSyncProvider",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Not found: \(identifier)"]
            )
        }
        return entry.data
    }

    @discardableResult
    func saveTemplate(_ data: Data, filename: String) async throws -> String {
        if let err = nextError { nextError = nil; throw err }
        saveTemplateCalls.append((filename, data.count))
        // Deliberately use a different-case identifier to exercise the
        // round-trip pattern — if `TemplateStore.delete` ever falls back to
        // a synthesized "/Templates/<filename>" path, the resulting case
        // mismatch would surface in `test_delete_uses_round_tripped_identifier`.
        let identifier = "/templates/\(filename.lowercased())"
        if let idx = stored.firstIndex(where: { $0.name == filename }) {
            stored[idx] = StoredTemplate(name: filename, identifier: identifier, data: data)
        } else {
            stored.append(StoredTemplate(name: filename, identifier: identifier, data: data))
        }
        return identifier
    }

    func deleteTemplate(at identifier: String) async throws {
        if let err = nextError { nextError = nil; throw err }
        deleteTemplateCalls.append(identifier)
        stored.removeAll { $0.identifier == identifier }
    }
}
