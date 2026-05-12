import Foundation

/// A signable form template. Pure data — UI and signature capture live elsewhere.
/// Codable so manager-authored templates can persist to JSON / Dropbox.
struct FormTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var header: FormHeader
    var content: FormContent
    var version: Int

    /// Bundled templates (e.g. the built-in sample) ship in the app binary;
    /// `editable == false` means the editor is read-only and Library hides delete.
    /// User-authored templates default to `true`.
    var editable: Bool

    init(
        id: UUID = UUID(),
        name: String,
        header: FormHeader,
        content: FormContent,
        version: Int = 1,
        editable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.header = header
        self.content = content
        self.version = version
        self.editable = editable
    }

    /// Backwards-compat decode: older bundled-only assumptions might omit `editable`.
    /// Default decoded value is `true` so user-uploaded JSON without the flag stays editable.
    enum CodingKeys: String, CodingKey {
        case id, name, header, content, version, editable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        header = try container.decode(FormHeader.self, forKey: .header)
        content = try container.decode(FormContent.self, forKey: .content)
        version = try container.decode(Int.self, forKey: .version)
        editable = try container.decodeIfPresent(Bool.self, forKey: .editable) ?? true
    }
}

/// Body content of a template — either the bundled "structured" form (intro +
/// numbered rules + acknowledgment) or a manager-authored freeform body.
enum FormContent: Codable, Hashable {
    case structured(intro: String, rules: [String], acknowledgment: String)
    case freeform(body: String)
}

struct FormHeader: Codable, Hashable {
    var company: String
    var location: String
    var department: String
    var effectiveDate: Date
}

extension FormHeader {
    /// Default header values applied to every new template. Phase 2 moves these
    /// into per-install `AppSettings` so a manager can fill them in once during
    /// setup; until then they render as obvious placeholders.
    static func placeholder(effectiveDate: Date = Date()) -> FormHeader {
        FormHeader(
            company: "Your Company",
            location: "Your Location",
            department: "Your Department",
            effectiveDate: effectiveDate
        )
    }
}

extension FormTemplate {
    /// Sentinel UUIDs for bundled templates. Held in a single place so
    /// `TemplateStore` can reject any synced JSON whose id matches — a malicious
    /// or accidentally-edited file on Dropbox can't impersonate a built-in.
    /// Future bundled templates extend this set; user-authored templates use
    /// `UUID()` and won't collide.
    enum BundledID {
        static let sampleAcknowledgmentV1 = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

        static let all: Set<UUID> = [sampleAcknowledgmentV1]
    }

    /// Built-in sample template — a generic placeholder so the library has
    /// something to show on first launch before a manager creates real templates.
    /// `editable: false` keeps it visible as documentation; managers replace
    /// it by tapping "New Template".
    static let sampleAcknowledgmentV1: FormTemplate = {
        return FormTemplate(
            id: BundledID.sampleAcknowledgmentV1,
            name: "Sample Acknowledgment Form",
            header: FormHeader(
                company: "Your Company",
                location: "Your Location",
                department: "Your Department",
                effectiveDate: Date()
            ),
            content: .structured(
                intro: "This is a sample template demonstrating the structured form layout. To create your own form, tap New Template — or replace this template with one that fits your organization.",
                rules: [
                    "Sample rule one — replace this text with content relevant to your form.",
                    "Sample rule two — rules render as a numbered list in the signed PDF.",
                    "Sample rule three — keep rules concise; the renderer surfaces an error if content overflows the page.",
                    "Sample rule four — add as many rules as your form requires."
                ],
                acknowledgment: "By signing below, I acknowledge that this is a sample form. Replace this template with one tailored to your organization before sharing it with signers."
            ),
            version: 1,
            editable: false
        )
    }()
}
