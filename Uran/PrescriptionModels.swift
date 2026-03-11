import Foundation

struct PrescriptionContainer: Codable, Hashable {
    var prescription: Prescription
}

struct Prescription: Codable, Hashable {
    var header: PrescriptionHeader
    var body: PrescriptionBody
    var signatura: PrescriptionSignatura
    var meta: PrescriptionMeta
}

struct PrescriptionHeader: Codable, Hashable {
    var id: String?
    var date: String?
    var patient: PrescriptionPatient?
    var doctor: String?
}

struct PrescriptionPatient: Codable, Hashable {
    var fullName: String?
    var ageYears: Int?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case ageYears = "age_years"
    }
}

struct PrescriptionBody: Codable, Hashable {
    var invocation: String
    var designatioMateriarum: [PrescriptionMaterial]
    var subscriptio: PrescriptionSubscriptio

    enum CodingKeys: String, CodingKey {
        case invocation
        case designatioMateriarum = "designatio_materiarum"
        case subscriptio
    }
}

struct PrescriptionMaterial: Codable, Hashable {
    var drugId: String?
    var nameLatinGenetivus: String
    var dosageValue: Double?
    var unit: String?
    var dosageRaw: String?

    enum CodingKeys: String, CodingKey {
        case drugId = "drug_id"
        case nameLatinGenetivus = "name_latin_genetivus"
        case dosageValue = "dosage_value"
        case unit
        case dosageRaw = "dosage_raw"
    }
}

struct PrescriptionSubscriptio: Codable, Hashable {
    var formShort: String
    var formFullLatin: String
    var amount: Int?
    var amountRaw: String?
    var instructionLatin: String
    var instructionShort: String

    enum CodingKeys: String, CodingKey {
        case formShort = "form_short"
        case formFullLatin = "form_full_latin"
        case amount
        case amountRaw = "amount_raw"
        case instructionLatin = "instruction_latin"
        case instructionShort = "instruction_short"
    }
}

struct PrescriptionSignatura: Codable, Hashable {
    var language: String
    var text: String
    var durationDays: Int?

    enum CodingKeys: String, CodingKey {
        case language
        case text
        case durationDays = "duration_days"
    }
}

struct PrescriptionMeta: Codable, Hashable {
    var isUrgent: Bool
    var isStale: Bool
    var storageLogic: String?

    enum CodingKeys: String, CodingKey {
        case isUrgent = "is_urgent"
        case isStale = "is_stale"
        case storageLogic = "storage_logic"
    }
}
