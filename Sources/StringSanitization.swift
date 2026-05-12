import Foundation

extension String {
    /// Strips every character Dropbox / macOS Finder / Windows Explorer would
    /// reject in a filename, plus C0 control chars. Also drops leading dots
    /// (which produce hidden files on macOS) and falls back to a literal
    /// placeholder when the result is empty.
    ///
    /// Used at both the template-name and signer-name positions of the
    /// `{Template} - {Signer} [{Date}].pdf` filename. Sanitizing both is what
    /// closes the path-injection vector the reviews flagged — without this, a
    /// template named `Onboarding/Customer` would create an `Onboarding`
    /// subfolder under `/Apps/SwiftPDF/Signed/`.
    func sanitizedForFilename(fallback: String = "Untitled") -> String {
        let disallowed = CharacterSet(charactersIn: "/\\<>:\"|?*")
            .union(.controlCharacters)
        var cleaned = unicodeScalars
            .split { disallowed.contains($0) }
            .map(String.init)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Truncates to a UTF-8 byte budget without splitting a multi-byte scalar.
    /// Dropbox enforces filename limits in bytes, not characters, so a name
    /// full of emoji or CJK can overflow a 255-byte cap at a much smaller
    /// `count`. Use this on the *whole* filename string just before appending
    /// the `.pdf` extension.
    func truncatedToUTF8Bytes(_ budget: Int) -> String {
        guard utf8.count > budget else { return self }
        var result = ""
        var bytes = 0
        for scalar in unicodeScalars {
            let scalarBytes = String(scalar).utf8.count
            if bytes + scalarBytes > budget { break }
            result.unicodeScalars.append(scalar)
            bytes += scalarBytes
        }
        return result
    }
}
