import Foundation

/// Reference to a single template file as enumerated by a sync provider.
/// `identifier` is provider-opaque: Dropbox stores a path string here, a
/// future Google Drive provider would store a fileId, an iCloud Drive
/// provider would store a URL string, etc. Callers must round-trip the
/// identifier verbatim into download / delete operations rather than
/// reconstructing it from `name` and a known folder constant — only the
/// provider knows how its identifiers compose.
struct TemplateRef: Sendable, Equatable {
    let name: String
    let identifier: String
}

/// Result of a signed-PDF upload. `path` is the provider-canonical location
/// where the file landed (Dropbox path, Drive fileId resolved-to-URL, NAS
/// share path); `wasAutorenamed` is true if the provider had to rename the
/// upload to avoid colliding with an existing sibling. Encapsulating both
/// here keeps each provider's path-compare and collision-detection rules
/// inside the provider — callers (e.g. `FormView`) consume the flag
/// directly instead of inferring it by string-comparing the request and
/// the response, which would have to know per-provider normalization rules
/// (NFC, case-insensitivity for Dropbox; different for Drive / iCloud).
struct UploadResult: Sendable, Equatable {
    let path: String
    let wasAutorenamed: Bool
}

/// CRUD surface that backs the template library and signed-PDF uploads. Each
/// cloud destination (Dropbox today; future Google Drive, iCloud Drive, NAS
/// over WebDAV) implements this protocol. Authentication flow is provider-
/// specific and lives on the concrete type — `SyncCoordinator` exposes typed
/// accessors so per-provider Connect views can drive their own OAuth /
/// credential entry.
/// `Sendable` so the task group inside `TemplateStore.refresh` can capture
/// the provider into non-isolated `group.addTask { }` closures for parallel
/// downloads. Conforming classes are @MainActor-isolated, which satisfies
/// the Sendable requirement for the receiver-hops-to-actor pattern.
@MainActor
protocol SyncProvider: AnyObject, Sendable {
    /// Uploads a signed PDF to the provider's configured signed-files
    /// location. Returns the resolved location and a flag indicating
    /// whether the provider had to rename the file to avoid collision —
    /// see `UploadResult`.
    func uploadSigned(_ pdfData: Data, filename: String) async throws -> UploadResult

    /// Lists template files in the provider's templates location. Returns
    /// an empty list when the folder does not yet exist — the first
    /// `saveTemplate` call creates it.
    func listTemplates() async throws -> [TemplateRef]

    /// Downloads a single template by the identifier returned from
    /// `listTemplates`.
    func downloadTemplate(at identifier: String) async throws -> Data

    /// Creates or overwrites a template by filename. Returns the canonical
    /// identifier of the saved file.
    @discardableResult
    func saveTemplate(_ data: Data, filename: String) async throws -> String

    /// Permanently removes a template by the identifier returned from
    /// `listTemplates`.
    func deleteTemplate(at identifier: String) async throws
}

/// Coordinator-level failures. Provider-specific errors (auth, network)
/// continue to surface from each concrete provider's own error enum —
/// this type carries only the cross-cutting cases the coordinator itself
/// produces.
enum SyncError: LocalizedError {
    /// Defensive guard: a CRUD method on the coordinator was reached while
    /// in demo preview. The demo branches in `TemplateStore` / `FormView`
    /// should intercept first; surfacing this case to the user indicates a
    /// missing demo branch in a caller, not a recoverable runtime state.
    case demoMode

    var errorDescription: String? {
        switch self {
        case .demoMode:
            return "Demo mode: cloud actions are disabled. Connect a sync provider to enable uploads."
        }
    }
}
