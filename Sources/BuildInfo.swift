import Foundation

/// Surfaces the public-source provenance of this build for the Settings → About
/// row. `SourceRepository` is hardcoded in `project.yml`'s Info.plist properties
/// and is intended to point at the public GitHub mirror. `SourceCommit` is
/// captured at build time by the `Inject source commit SHA` preBuildScript
/// (also in `project.yml`).
///
/// Production builds intended for App Store submission should be made from a
/// fresh clone of the public repository — the SHA shown here will then match
/// a real, reviewable commit anyone can inspect.
enum BuildInfo {
    /// Public source repository root URL (no commit suffix).
    static let sourceRepository: String = {
        Bundle.main.object(forInfoDictionaryKey: "SourceRepository") as? String ?? "unknown"
    }()

    /// Commit SHA captured at build time. May carry a `-dirty` suffix if the
    /// working tree had uncommitted changes when the build ran (this is a
    /// deliberate honesty signal — a dirty build doesn't perfectly correspond
    /// to any single commit in the public repo).
    static let sourceCommit: String = {
        Bundle.main.object(forInfoDictionaryKey: "SourceCommit") as? String ?? "unknown"
    }()

    /// Compact 7-char form of the commit SHA, preserving any `-dirty` suffix.
    static var sourceCommitShort: String {
        let raw = sourceCommit
        guard raw != "unknown" else { return raw }
        let (hash, suffix) = splitDirtySuffix(raw)
        let short = String(hash.prefix(7))
        return short + suffix
    }

    /// URL that opens the displayed commit on the public repo. The `-dirty`
    /// suffix is stripped for URL construction (GitHub doesn't recognize it),
    /// but the displayed SHA elsewhere still shows it.
    static var sourceCommitURL: URL? {
        guard sourceRepository != "unknown" else { return nil }
        let (cleanHash, _) = splitDirtySuffix(sourceCommit)
        guard cleanHash != "unknown", !cleanHash.isEmpty else {
            return URL(string: sourceRepository)
        }
        return URL(string: "\(sourceRepository)/commit/\(cleanHash)")
    }

    /// Marketing version, e.g. "1.0.0".
    static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }()

    /// Build number (monotonic per Apple's rules), e.g. "1".
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }()

    private static func splitDirtySuffix(_ raw: String) -> (hash: String, suffix: String) {
        if let range = raw.range(of: "-dirty") {
            return (String(raw[..<range.lowerBound]), String(raw[range.lowerBound...]))
        }
        return (raw, "")
    }
}
