import Foundation

/// A signable form template. Pure data — UI and signature capture live elsewhere.
/// Codable so phase-2 template editing can persist to JSON / Dropbox.
struct FormTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var header: FormHeader
    var intro: String
    var rules: [String]
    var acknowledgment: String
    var version: Int

    init(
        id: UUID = UUID(),
        name: String,
        header: FormHeader,
        intro: String,
        rules: [String],
        acknowledgment: String,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.header = header
        self.intro = intro
        self.rules = rules
        self.acknowledgment = acknowledgment
        self.version = version
    }
}

struct FormHeader: Codable, Equatable {
    var company: String
    var location: String
    var department: String
    var effectiveDate: Date
}

extension FormTemplate {
    /// Built-in General Safety Rules template — seeded from the original Word doc content.
    /// Phase 2 will let managers edit / replace this in-app.
    static let generalSafetyV1: FormTemplate = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let effective = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!

        return FormTemplate(
            name: "General Safety Rules",
            header: FormHeader(
                company: "KwikShip, LLC",
                location: "981 Industrial Park Road Columbia, TN 38401",
                department: "Fulfillment / Distribution / Warehousing",
                effectiveDate: effective
            ),
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
            acknowledgment: "By signing below, I acknowledge that I have read, understand, and agree to comply with these General Safety Rules while on KwikShip, LLC property or performing work on behalf of KwikShip, LLC.",
            version: 1
        )
    }()
}
