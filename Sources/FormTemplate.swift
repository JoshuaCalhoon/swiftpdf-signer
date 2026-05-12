import Foundation

/// A signable form template. Pure data — UI and signature capture live elsewhere.
/// Codable so manager-authored templates can persist to JSON / Dropbox.
struct FormTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var header: FormHeader
    var content: FormContent
    var version: Int

    /// Bundled templates (e.g. General Safety) ship in the app binary;
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
    /// Locked KwikShip header values reused for every manager-authored template.
    /// `effectiveDate` defaults to the moment the template is created.
    static func kwikshipStandard(effectiveDate: Date = Date()) -> FormHeader {
        FormHeader(
            company: "KwikShip, LLC",
            location: "981 Industrial Park Road Columbia, TN 38401",
            department: "Fulfillment / Distribution / Warehousing",
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
        static let generalSafetyV1 = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

        static let all: Set<UUID> = [generalSafetyV1]
    }

    /// Built-in General Safety Rules template — seeded from the original Word doc content.
    /// Phase 2 will let managers edit / replace this in-app.
    static let generalSafetyV1: FormTemplate = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        // `calendar.date(from:)` can theoretically return nil for invalid
        // components. The hardcoded values here are valid, so this is a
        // shouldn't-happen path — but a future typo (`day: 32`) would crash
        // at first access otherwise. Fall back to `Date()` to keep the app
        // launchable; the rendered form's "Effective Date" will then read
        // as today, which is loud enough that someone notices and fixes it.
        let effective = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22)) ?? Date()

        return FormTemplate(
            id: BundledID.generalSafetyV1,
            name: "General Safety Rules",
            header: FormHeader(
                company: "KwikShip, LLC",
                location: "981 Industrial Park Road Columbia, TN 38401",
                department: "Fulfillment / Distribution / Warehousing",
                effectiveDate: effective
            ),
            content: .structured(
                intro: "All employees, temporary workers, contractors, and visitors are expected to follow these general safety rules while on company property or performing work on behalf of KwikShip, LLC.",
                rules: [
                    "Follow all company safety rules, procedures, and posted instructions.",
                    "Report all injuries, incidents, near misses, hazards, and unsafe conditions immediately.",
                    "Stop work and ask for guidance if a task cannot be completed safely.",
                    "Wear required PPE and use equipment only as trained and authorized.",
                    "Keep work areas clean, organized, and free of slip, trip, and fire hazards.",
                    "Keep aisles, exits, fire extinguishers, electrical panels, and emergency equipment clear at all times.",
                    "Clean up spills promptly or report them immediately.",
                    "Use safe lifting practices and get help when needed.",
                    "Only trained and authorized employees may operate forklifts or other powered industrial trucks and must have a spotter when storing pallets in racks.",
                    "Stay alert to moving equipment, pedestrians, dock areas, and material handling hazards.",
                    "Do not remove guards, bypass safety devices, or use damaged tools or equipment.",
                    "Horseplay, running, fighting, or other unsafe behavior is not permitted.",
                    "Follow all emergency procedures, alarms, drills, and evacuation instructions.",
                    "Know the location of emergency exits, first aid kits, and fire extinguishers in your work area.",
                    "Safety is a shared responsibility, and all employees are expected to help maintain a safe workplace."
                ],
                acknowledgment: "By signing below, I acknowledge that I have read, understand, and agree to comply with these General Safety Rules while on KwikShip, LLC property or performing work on behalf of KwikShip, LLC."
            ),
            version: 1,
            editable: false
        )
    }()
}
