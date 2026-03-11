import Foundation

enum DissolutionType: String, Codable, CaseIterable, Sendable {
    case ordinary
    case hmcUnrestricted
    case hmcRestrictedHeat
    case hmcRestrictedCool
    case colloidProtargol
    case colloidCollargol
    case ichthyol
}

struct ExtempSubstance: Identifiable, Hashable {
    let id: Int
    let innKey: String
    let categoryId: Int
    let nameRu: String
    let nameLatNom: String
    let nameLatGen: String
    let role: String
    let refType: String
    let isColoring: Bool
    let vrdG: Double?
    let vsdG: Double?
    let pedsVrdG: Double?
    let pedsRdG: Double?
    let vrdChild0_1: Double?
    let vrdChild1_6: Double?
    let vrdChild7_14: Double?
    let kuoMlPerG: Double?
    let kvGPer100G: Double?
    let gttsPerMl: Double?
    let eFactor: Double?
    let density: Double?
    let solubility: String?
    let storage: String?
    let interactionNotes: String?
    let ointmentEntryType: String?
    let ointmentSolventInnKey: String?
    let ointmentRatioSoluteToSolvent: Double?
    let ointmentNote: String?
    let needsTrituration: Bool
    let listA: Bool
    let listB: Bool
    let isNarcotic: Bool
    let pharmActivity: String?
    let physicalState: String?

    // Herbal technology
    let prepMethod: String?
    let herbalRatio: String?
    let waterTempC: Double?
    let heatBathMin: Int?
    let standMin: Int?
    let coolMin: Int?
    let strain: Bool
    let pressMarc: Bool
    let bringToVolume: Bool
    let shelfLifeHours: Int?
    let storagePrepared: String?

    // Tincture technology
    let extractionSolvent: String?
    let tinctureRatio: String?
    let macerationDays: Int?
    let shakeDaily: Bool
    let filter: Bool
    let storageTincture: String?

    // Extract technology
    let extractType: String?
    let extractSolvent: String?
    let extractRatio: String?

    // Buffer/Solvent/Base short hints
    let bufferPH: Double?
    let bufferMolarity: Double?
    let solventType: String?
    let sterile: Bool
    var isVolatile: Bool? = nil
    var isFlammable: Bool? = nil
    var heatingAllowed: NonAqueousHeatingAllowance? = nil
    var heatingTempMaxC: Double? = nil
    var defaultEthanolStrength: Int? = nil
    var incompatibleWithEthanol: Bool? = nil

    let dissolutionType: DissolutionType?
}

extension ExtempSubstance {
    var isHardToGrind: Bool {
        let key = innKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = (key.isEmpty ? name : key) + " " + name

        if hay.contains("camphor") { return true }
        if hay.contains("menthol") { return true }
        if hay.contains("thymol") { return true }
        if hay.contains("acidum salicylic") { return true }
        if hay.contains("salicylicum") { return true }
        if hay.contains("phenylii salicyl") { return true }
        if hay.contains("phenylis salicyl") { return true }

        return false
    }
}

struct ExtempStorageRule: Identifiable, Hashable {
    let id: UUID
    let substanceId: Int
    let propertyTitleUk: String
    let extraConditionsUk: String
    let nameLatNom: String
    let nameLatGen: String
    let listCode: String
    let noteUk: String

    init(
        substanceId: Int,
        propertyTitleUk: String,
        extraConditionsUk: String,
        nameLatNom: String,
        nameLatGen: String,
        listCode: String,
        noteUk: String
    ) {
        self.id = UUID()
        self.substanceId = substanceId
        self.propertyTitleUk = propertyTitleUk
        self.extraConditionsUk = extraConditionsUk
        self.nameLatNom = nameLatNom
        self.nameLatGen = nameLatGen
        self.listCode = listCode
        self.noteUk = noteUk
    }
}

struct ExtempUnit: Identifiable, Hashable {
    let id: Int
    let code: String
    let nameRu: String
    let lat: String
}

struct ExtempDosageForm: Identifiable, Hashable {
    let id: Int
    let code: String
    let nameRu: String
    let latMf: String
}

struct ExtempMfRule: Identifiable, Hashable {
    let id: Int
    let priority: Int
    let formId: Int
    let ruleName: String
    let ifAnyRole: String
    let ifAnySubstanceInnKey: String
}

enum ExtempRepositoryError: Error, LocalizedError {
    case dbNotFound
    case dbEmpty
    case schemaInvalid(String)

    var errorDescription: String? {
        switch self {
        case .dbNotFound:
            return "pharma_optimized.db не найден в app bundle. Проверь Target Membership / Copy Bundle Resources"
        case .dbEmpty:
            return "pharma_optimized.db имеет нулевой размер. Проверь, что в Bundle Resources добавлен настоящий файл базы данных (не пустой)"
        case .schemaInvalid(let message):
            return message
        }
    }
}

final class ExtempRepository {
    private let queue = DispatchQueue(label: "extemp.sqlite.queue")
    private let sqlite: SQLiteService
    private let dbPath: String

    private static func detectListBFlag(
        explicitFlag: Bool,
        refType: String?,
        pharmActivity: String?,
        storage: String?,
        ointmentNote: String?
    ) -> Bool {
        if explicitFlag { return true }

        func normalized(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        func isAuxiliaryLike(_ value: String?) -> Bool {
            ["aux", "solv", "solvent", "base", "viscous liquid", "standardsolution", "liquidstandard"].contains(normalized(value))
        }

        func containsNegativeStrongMarker(_ text: String) -> Bool {
            text.contains("несильнод")
                || text.contains("не сильнод")
                || text.contains("несильнодейств")
                || text.contains("не сильнодейств")
                || text.contains("non-strong")
                || text.contains("non strong")
                || text.contains("not strong")
        }

        func containsPositiveStrongMarker(_ text: String) -> Bool {
            guard !containsNegativeStrongMarker(text) else { return false }
            return text.contains("сильнод")
                || text.contains("сильнодейств")
                || text.contains("heroica")
                || text.contains("strong")
        }

        let activity = normalized(pharmActivity)
        if !isAuxiliaryLike(refType), containsPositiveStrongMarker(activity)
        {
            return true
        }

        let storageText = normalized(storage)
        if storageText.contains("список б")
            || storageText.contains("list b")
            || storageText.contains("heroica")
        {
            return true
        }

        let ointment = normalized(ointmentNote)
        return containsPositiveStrongMarker(ointment)
            || ointment.contains("список б")
            || ointment.contains("list b")
    }

    private static func normalizeReferenceType(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        let lower = trimmed.lowercased()
        let compact = lower.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        switch compact {
        case "act", "active", "activeingredient", "substance", "substantia", "medicinalsubstance":
            return "act"
        case "aux", "auxiliary", "excipient":
            return "aux"
        case "solv", "solvent", "diluent", "vehicle":
            return "solvent"
        case "base", "ointmentbase", "oilbase", "fattybase", "hydrophobicbase":
            return "base"
        case "polymerbase", "isotonicbase":
            return "base"
        case "buffersolution", "buffer":
            return "buffersolution"
        case "tincture":
            return "tincture"
        case "extract":
            return "extract"
        case "syrup":
            return "syrup"
        case "juice":
            return "juice"
        case "suspension":
            return "suspension"
        case "emulsion":
            return "emulsion"
        case "herbalraw":
            return "herbalraw"
        case "herbalmix":
            return "herbalmix"
        case "ointmentphyto", "topicalphytomodern", "insolublepowder":
            return "act"
        case "liquidstandard", "standardliquid", "standardsolution", "standardstocksolution", "officinalsolution":
            return "standardsolution"
        case "viscousliquid":
            return "viscous liquid"
        case "liquid", "жидкие", "жидкая", "жидкий", "рідкі", "рідка", "рідкий":
            return "liquid"
        case "твердые", "твердый", "твердое", "твердыи", "тверда", "твердий", "тверде":
            return "act"
        case "alcoholic":
            return "alcoholic"
        default:
            return lower
        }
    }

    init() throws {
        guard let url = Bundle.main.url(forResource: "pharma_optimized", withExtension: "db") else {
            throw ExtempRepositoryError.dbNotFound
        }

        let targetFileName = "pharma_optimized.db"
        let fm = FileManager.default
        let supportDir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)

        let targetUrl = supportDir.appendingPathComponent(targetFileName)

        let bundleAttrs = try? fm.attributesOfItem(atPath: url.path)
        let targetAttrs = try? fm.attributesOfItem(atPath: targetUrl.path)

        let bundleSize = bundleAttrs?[.size] as? NSNumber
        let targetSize = targetAttrs?[.size] as? NSNumber
        let bundleMTime = bundleAttrs?[.modificationDate] as? Date
        let targetMTime = targetAttrs?[.modificationDate] as? Date

        let needsRefresh: Bool
        if !fm.fileExists(atPath: targetUrl.path) {
            needsRefresh = true
        } else if bundleSize != nil, targetSize != nil, bundleSize != targetSize {
            needsRefresh = true
        } else if let bundleMTime, let targetMTime, bundleMTime > targetMTime {
            needsRefresh = true
        } else {
            needsRefresh = false
        }

        if needsRefresh {
            if fm.fileExists(atPath: targetUrl.path) {
                try? fm.removeItem(at: targetUrl)
            }
            try fm.copyItem(at: url, to: targetUrl)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: targetUrl.path)
        }

        if let attrs = try? fm.attributesOfItem(atPath: targetUrl.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue <= 0 {
            throw ExtempRepositoryError.dbEmpty
        }

        self.dbPath = targetUrl.path
        self.sqlite = try SQLiteService(readOnlyDatabaseAtPath: self.dbPath)

        try validateSchema()
        try ensureIncompatibilitiesSchema()
        try ensureExtempReferenceSchemaAndImport()
        try ensureSolventProfilesImport()

        print("ExtempRepository DB:", self.dbPath)
    }

    private func validateSchema() throws {
    }

    private func ensureExtempReferenceSchemaAndImport() throws {
        try sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS extemp_reference_substances (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name_lat_nom TEXT NOT NULL,
                name_lat_gen TEXT NOT NULL,
                name_ru_ref TEXT,
                type TEXT NOT NULL,
                is_coloring INTEGER DEFAULT 0,
                vrd_g REAL,
                vsd_g REAL,
                peds_vrd_g REAL,
                peds_rd_g REAL,
                vrd_child_0_1 REAL,
                vrd_child_1_6 REAL,
                vrd_child_7_14 REAL,
                kuo_ml_per_g REAL,
                kv_g_per_100g REAL,
                gtts_per_ml REAL,
                e_factor REAL,
                density REAL,
                solubility TEXT,
                storage TEXT,
                interaction_notes TEXT,
                ointment_entry_type TEXT,
                ointment_solvent_inn_key TEXT,
                ointment_ratio_solute_to_solvent REAL,
                ointment_note TEXT,
                needs_trituration INTEGER DEFAULT 0,
                list_a INTEGER DEFAULT 0,
                list_b INTEGER DEFAULT 0,
                is_narcotic INTEGER DEFAULT 0,
                pharm_activity TEXT,
                physical_state TEXT,

                prep_method TEXT,
                herbal_ratio TEXT,
                water_temp_c REAL,
                heat_bath_min INTEGER,
                stand_min INTEGER,
                cool_min INTEGER,
                strain INTEGER DEFAULT 0,
                press_marc INTEGER DEFAULT 0,
                bring_to_volume INTEGER DEFAULT 0,
                shelf_life_hours INTEGER,
                storage_prepared TEXT,

                extraction_solvent TEXT,
                tincture_ratio TEXT,
                maceration_days INTEGER,
                shake_daily INTEGER DEFAULT 0,
                filter INTEGER DEFAULT 0,
                storage_tincture TEXT,

                extract_type TEXT,
                extract_solvent TEXT,
                extract_ratio TEXT,

                buffer_ph REAL,
                buffer_molarity REAL,
                solvent_type TEXT,
                sterile INTEGER DEFAULT 0,
                is_volatile INTEGER DEFAULT 0,
                is_flammable INTEGER DEFAULT 0,
                heating_allowed TEXT,
                heating_temp_max_c REAL,
                default_ethanol_strength INTEGER,
                incompatible_with_ethanol INTEGER DEFAULT 0,
                dissolution_type TEXT,
                source TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            );
            """
        )

        // Migrate older installs (table existed before coefficients were introduced).
        let cols = try sqlite.queryRows(
            sql: "PRAGMA table_info(extemp_reference_substances);",
            binds: []
        )
        let existing = Set(cols.compactMap { (($0["name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !existing.contains("name_ru_ref") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN name_ru_ref TEXT;", binds: [])
        }
        if !existing.contains("kuo_ml_per_g") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN kuo_ml_per_g REAL;", binds: [])
        }
        if !existing.contains("kv_g_per_100g") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN kv_g_per_100g REAL;", binds: [])
        }
        if !existing.contains("gtts_per_ml") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN gtts_per_ml REAL;", binds: [])
        }
        if !existing.contains("solubility") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN solubility TEXT;", binds: [])
        }
        if !existing.contains("storage") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN storage TEXT;", binds: [])
        }
        if !existing.contains("interaction_notes") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN interaction_notes TEXT;", binds: [])
        }
        if !existing.contains("e_factor") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN e_factor REAL;", binds: [])
        }
        if !existing.contains("density") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN density REAL;", binds: [])
        }
        if !existing.contains("peds_vrd_g") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN peds_vrd_g REAL;", binds: [])
        }
        if !existing.contains("peds_rd_g") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN peds_rd_g REAL;", binds: [])
        }
        if !existing.contains("vrd_child_0_1") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN vrd_child_0_1 REAL;", binds: [])
        }
        if !existing.contains("vrd_child_1_6") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN vrd_child_1_6 REAL;", binds: [])
        }
        if !existing.contains("vrd_child_7_14") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN vrd_child_7_14 REAL;", binds: [])
        }
        if !existing.contains("is_coloring") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN is_coloring INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("ointment_entry_type") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN ointment_entry_type TEXT;", binds: [])
        }
        if !existing.contains("ointment_solvent_inn_key") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN ointment_solvent_inn_key TEXT;", binds: [])
        }
        if !existing.contains("ointment_ratio_solute_to_solvent") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN ointment_ratio_solute_to_solvent REAL;", binds: [])
        }
        if !existing.contains("ointment_note") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN ointment_note TEXT;", binds: [])
        }
        if !existing.contains("needs_trituration") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN needs_trituration INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("list_a") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN list_a INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("list_b") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN list_b INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("is_narcotic") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN is_narcotic INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("pharm_activity") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN pharm_activity TEXT;", binds: [])
        }
        if !existing.contains("physical_state") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN physical_state TEXT;", binds: [])
        }

        if !existing.contains("prep_method") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN prep_method TEXT;", binds: [])
        }
        if !existing.contains("herbal_ratio") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN herbal_ratio TEXT;", binds: [])
        }
        if !existing.contains("water_temp_c") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN water_temp_c REAL;", binds: [])
        }
        if !existing.contains("heat_bath_min") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN heat_bath_min INTEGER;", binds: [])
        }
        if !existing.contains("stand_min") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN stand_min INTEGER;", binds: [])
        }
        if !existing.contains("cool_min") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN cool_min INTEGER;", binds: [])
        }
        if !existing.contains("strain") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN strain INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("press_marc") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN press_marc INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("bring_to_volume") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN bring_to_volume INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("shelf_life_hours") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN shelf_life_hours INTEGER;", binds: [])
        }
        if !existing.contains("storage_prepared") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN storage_prepared TEXT;", binds: [])
        }

        if !existing.contains("extraction_solvent") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN extraction_solvent TEXT;", binds: [])
        }
        if !existing.contains("tincture_ratio") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN tincture_ratio TEXT;", binds: [])
        }
        if !existing.contains("maceration_days") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN maceration_days INTEGER;", binds: [])
        }
        if !existing.contains("shake_daily") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN shake_daily INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("filter") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN filter INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("storage_tincture") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN storage_tincture TEXT;", binds: [])
        }

        if !existing.contains("extract_type") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN extract_type TEXT;", binds: [])
        }
        if !existing.contains("extract_solvent") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN extract_solvent TEXT;", binds: [])
        }
        if !existing.contains("extract_ratio") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN extract_ratio TEXT;", binds: [])
        }

        if !existing.contains("buffer_ph") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN buffer_ph REAL;", binds: [])
        }
        if !existing.contains("buffer_molarity") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN buffer_molarity REAL;", binds: [])
        }
        if !existing.contains("solvent_type") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN solvent_type TEXT;", binds: [])
        }
        if !existing.contains("sterile") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN sterile INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("is_volatile") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN is_volatile INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("is_flammable") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN is_flammable INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("heating_allowed") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN heating_allowed TEXT;", binds: [])
        }
        if !existing.contains("heating_temp_max_c") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN heating_temp_max_c REAL;", binds: [])
        }
        if !existing.contains("default_ethanol_strength") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN default_ethanol_strength INTEGER;", binds: [])
        }
        if !existing.contains("incompatible_with_ethanol") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN incompatible_with_ethanol INTEGER DEFAULT 0;", binds: [])
        }
        if !existing.contains("dissolution_type") {
            try sqlite.execute(sql: "ALTER TABLE extemp_reference_substances ADD COLUMN dissolution_type TEXT;", binds: [])
        }
        try sqlite.execute(
            sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_extemp_reference_substances_nom
            ON extemp_reference_substances(name_lat_nom);
            """
        )

        guard let csvUrl = Bundle.main.url(forResource: "extemp_reference_200", withExtension: "csv") else {
            // Table exists but no seed file in bundle.
            // This is not fatal for the app; the constructor can still use `substances`.
            return
        }

        let csv = (try? String(contentsOf: csvUrl, encoding: .utf8)) ?? ""
        if csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        try sqlite.execute(
            sql: """
            DELETE FROM extemp_reference_substances
            WHERE source = 'extemp_reference_200.csv';
            """,
            binds: []
        )

        let parsed = parseCsvWithHeader(csv)
        func normalizedHeaderKey(_ raw: String) -> String {
            let cleaned = raw
                .replacingOccurrences(of: "\u{feff}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let scalars = cleaned.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            return String(String.UnicodeScalarView(scalars))
        }
        let headerIndex: [String: Int] = {
            var m: [String: Int] = [:]
            for (idx, h) in parsed.header.enumerated() {
                let keyRaw = h
                    .replacingOccurrences(of: "\u{feff}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let keyNormalized = normalizedHeaderKey(h)
                if !keyRaw.isEmpty, m[keyRaw] == nil { m[keyRaw] = idx }
                if !keyNormalized.isEmpty, m[keyNormalized] == nil { m[keyNormalized] = idx }
            }
            return m
        }()

        func idx(_ names: String...) -> Int? {
            for name in names {
                let keyRaw = name
                    .replacingOccurrences(of: "\u{feff}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if let i = headerIndex[keyRaw] { return i }

                let keyNormalized = normalizedHeaderKey(name)
                if let i = headerIndex[keyNormalized] { return i }
            }
            return nil
        }

        func cleaned(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func toOptionalDouble(_ s: String) -> Double? {
            let v = cleaned(s)
            if v.isEmpty || v == "-" { return nil }
            return Double(v.replacingOccurrences(of: ",", with: "."))
        }

        func toOptionalInt(_ s: String) -> Int? {
            let v = cleaned(s)
            if v.isEmpty || v == "-" { return nil }
            if let i = Int(v) { return i }
            if let d = Double(v.replacingOccurrences(of: ",", with: ".")) {
                return Int(d.rounded())
            }
            return nil
        }

        func toBoolFlag(_ s: String) -> Bool {
            let v = cleaned(s).lowercased()
            if v.isEmpty { return false }
            let truthy: Set<String> = ["yes", "y", "true", "1", "так", "да", "+"]
            let falsy: Set<String> = ["no", "n", "false", "0", "ні", "нет", "-"]
            if truthy.contains(v) { return true }
            if falsy.contains(v) { return false }
            return v.contains("yes") || v.contains("true") || v.contains("так") || v.contains("да")
        }

        func isBoolLike(_ s: String) -> Bool {
            let v = cleaned(s).lowercased()
            if v.isEmpty { return false }
            let boolLike: Set<String> = ["yes", "y", "true", "1", "так", "да", "+", "no", "n", "false", "0", "ні", "нет", "-"]
            return boolLike.contains(v)
        }

        func isGenericPhysicalStateTag(_ s: String) -> Bool {
            let v = cleaned(s).lowercased()
            if v.isEmpty { return false }
            let generic: Set<String> = [
                "solid", "solids", "liquid", "liquids",
                "твердий", "тверда", "тверде", "твердые", "твердое",
                "рідкий", "рідка", "рідке", "жидкий", "жидкая", "жидкие"
            ]
            return generic.contains(v)
        }

        func looksLikeDetailedPhysicalDescription(_ s: String) -> Bool {
            let v = cleaned(s).lowercased()
            if v.isEmpty || isBoolLike(v) { return false }
            let markers = ["порош", "кристал", "без запах", "odorless", "powder", "crystal", "рідина", "жидк", "гигроскоп", "гігроскоп"]
            return v.count >= 12 && markers.contains(where: { v.contains($0) })
        }

        func firstNonEmpty(_ values: String...) -> String {
            for value in values {
                let trimmed = cleaned(value)
                if !trimmed.isEmpty { return trimmed }
            }
            return ""
        }

        var seenNomKeys: Set<String> = []
        for r in parsed.rows {
            guard r.count >= 3 else { continue }

            // Prefer header-based mapping. If header doesn't look like a header, fall back to positional parsing.
            let headerLooksValid: Bool = {
                if idx("namelatnom") != nil { return true }
                if idx("name_lat_nom") != nil { return true }
                return false
            }()

            let nom: String
            let gen: String
            let nameRuRef: String?
            let type: String
            let isColoring: Bool
            let vrd: Double?
            let vsd: Double?
            let pedsVrd: Double?
            let pedsRd: Double?
            let vrdChild0_1: Double?
            let vrdChild1_6: Double?
            let vrdChild7_14: Double?
            let kuo: Double?
            let kv: Double?
            let gttsPerMl: Double?
            let eFactor: Double?
            let density: Double?
            let solubility: String?
            let storage: String?
            let interactionNotes: String?
            let ointmentEntryType: String?
            let ointmentSolventInnKey: String?
            let ointmentRatioSoluteToSolvent: Double?
            let ointmentNote: String?
            let needsTrituration: Bool
            let listA: Bool
            let listB: Bool
            let isNarcotic: Bool
            let pharmActivity: String?
            let physicalState: String?

            var prepMethod: String?
            let herbalRatio: String?
            let waterTempC: Double?
            let heatBathMin: Int?
            let standMin: Int?
            let coolMin: Int?
            let strain: Bool
            let pressMarc: Bool
            let bringToVolume: Bool
            let shelfLifeHours: Int?
            let storagePrepared: String?

            let extractionSolvent: String?
            let tinctureRatio: String?
            let macerationDays: Int?
            let shakeDaily: Bool
            let filter: Bool
            let storageTincture: String?

            let extractType: String?
            let extractSolvent: String?
            let extractRatio: String?

            let bufferPH: Double?
            let bufferMolarity: Double?
            var solventType: String?
            let sterile: Bool

            let dissolutionType: DissolutionType?

            if headerLooksValid {
                func str(_ key: String) -> String {
                    guard let i = idx(key), i < r.count else { return "" }
                    return cleaned(r[i])
                }
                func num(_ key: String) -> Double? {
                    guard let i = idx(key), i < r.count else { return nil }
                    return toOptionalDouble(r[i])
                }

                nom = str("namelatnom").isEmpty ? str("name_lat_nom") : str("namelatnom")
                gen = str("namelatgen").isEmpty ? str("name_lat_gen") : str("namelatgen")
                let ru = firstNonEmpty(str("rus"), str("name_ru"), str("nameru"))
                nameRuRef = ru.isEmpty ? nil : ru
                type = Self.normalizeReferenceType(firstNonEmpty(str("type"), str("ref_type")))
                isColoring = toBoolFlag(str("iscoloring")) || toBoolFlag(str("is_coloring"))
                vrd = num("vrdg").flatMap { $0 } ?? num("vrd_g")
                vsd = num("vsdg").flatMap { $0 } ?? num("vsd_g")
                pedsVrd = num("pedsvrdg") ?? num("peds_vrd_g")
                pedsRd = num("pedsrdg") ?? num("peds_rd_g")
                vrdChild0_1 = num("vrdchild_0_1") ?? num("vrd_child_0_1")
                vrdChild1_6 = num("vrdchild_1_6") ?? num("vrd_child_1_6")
                vrdChild7_14 = num("vrdchild_7_14") ?? num("vrd_child_7_14")
                kuo = num("kuo") ?? num("kuo (мл/г)") ?? num("kuo_ml_per_g") ?? num("kuo_water")
                kv = num("kv") ?? num("kv (г/100г)") ?? num("kv_g_per_100g")
                gttsPerMl = num("gttsperml") ?? num("gtts_per_ml")
                eFactor = num("e_factor") ?? num("efactor") ?? num("e") ?? num("e-factor") ?? num("e factor")
                density = num("density") ?? num("rho")
                let sol = str("solubility")
                solubility = sol.isEmpty ? nil : sol
                let processNoteRaw = firstNonEmpty(str("process_note"), str("processnote"), str("process"))
                let instructionIdRaw = firstNonEmpty(str("instruction_id"), str("instructionid"))
                let solubilitySpeedRaw = firstNonEmpty(str("solubility_speed"), str("solubilityspeed"))
                let methodTypeRaw = firstNonEmpty(str("method_type"), str("methodtype"))
                let filterTypeRaw = firstNonEmpty(str("filter_type"), str("filtertype"))
                let needsIsotonizationRaw = firstNonEmpty(
                    str("needs_isotonization"),
                    str("needsisotonization"),
                    str("needs_isotonisation"),
                    str("needsisotonisation")
                )

                var storageRaw = str("storage")
                let lightSensitive = toBoolFlag(firstNonEmpty(str("light_sensitive"), str("lightsensitive")))
                if lightSensitive, !storageRaw.lowercased().contains("light") {
                    storageRaw = storageRaw.isEmpty ? "LightProtected" : "\(storageRaw); LightProtected"
                }
                let hygroscopic = toBoolFlag(firstNonEmpty(str("is_hygroscopic"), str("ishygroscopic")))
                if hygroscopic, !storageRaw.lowercased().contains("dry") {
                    storageRaw = storageRaw.isEmpty ? "DryPlace" : "\(storageRaw); DryPlace"
                }
                storage = storageRaw.isEmpty ? nil : storageRaw

                var inx = str("interactionnotes")
                if !instructionIdRaw.isEmpty, !inx.lowercased().contains(instructionIdRaw.lowercased()) {
                    inx = inx.isEmpty ? instructionIdRaw : "\(inx); \(instructionIdRaw)"
                }
                if !processNoteRaw.isEmpty, !inx.lowercased().contains(processNoteRaw.lowercased()) {
                    inx = inx.isEmpty ? processNoteRaw : "\(inx); \(processNoteRaw)"
                }
                interactionNotes = inx.isEmpty ? nil : inx

                let oType = str("ointment_entry_type")
                ointmentEntryType = oType.isEmpty ? nil : oType
                let oSolv = str("ointment_solvent_inn_key")
                ointmentSolventInnKey = oSolv.isEmpty ? nil : oSolv
                ointmentRatioSoluteToSolvent = num("ointment_ratio_solute_to_solvent")
                let oNote = str("ointment_note")
                ointmentNote = oNote.isEmpty ? nil : oNote

                needsTrituration = toBoolFlag(str("needstrituration"))
                let rawIsListAPoison = firstNonEmpty(
                    str("islista_poison"),
                    str("islistapoison"),
                    str("slista_poison"),
                    str("slistapoison"),
                    str("islista")
                )
                let rawNaturalGroup = firstNonEmpty(str("naturalgroup"), str("natural_group"))
                let isListAPoison: Bool = {
                    if isBoolLike(rawIsListAPoison) { return toBoolFlag(rawIsListAPoison) }
                    if isBoolLike(rawNaturalGroup) { return toBoolFlag(rawNaturalGroup) }
                    return false
                }()
                let markerHay = "\(instructionIdRaw) \(processNoteRaw)".lowercased()
                let hasDoubleControlA = markerHay.contains("double_control_a")
                    || markerHay.contains("doublecontrola")
                let isNatriiBromidum = nom.lowercased().contains("natrii bromid")
                let isBoricAntiseptic: Bool = {
                    let hay = "\(nom) \(gen) \(nameRuRef ?? "")".lowercased()
                    return hay.contains("acidum boric")
                        || hay.contains("acidi borici")
                        || hay.contains("boric acid")
                        || hay.contains("spiritus boric")
                        || hay.contains("spiritus borici")
                        || hay.contains("борн")
                }()
                let isEthanolAccountingSolvent: Bool = {
                    let hay = "\(nom) \(gen) \(nameRuRef ?? "") \(type)".lowercased()
                    let hasEthanolMarker = hay.contains("spiritus aethylic")
                        || hay.contains("spiritus vini")
                        || hay.contains("ethanol")
                        || hay.contains("ethanolum")
                        || hay.contains("ethyl alcohol")
                        || hay.contains("спирт этил")
                        || hay.contains("спирт етил")
                    let solventLikeType = ["solv", "solvent", "aux", "standardsolution", "liquidstandard", "alcoholic"].contains(type)
                    return hasEthanolMarker && solventLikeType
                }()
                listA = (toBoolFlag(str("list_a")) || isListAPoison || hasDoubleControlA)
                    && !isNatriiBromidum
                    && !isBoricAntiseptic
                    && !isEthanolAccountingSolvent
                isNarcotic = toBoolFlag(str("isnarcotic"))
                let byCompositionRaw = firstNonEmpty(str("bycomposition"), str("by_composition"))
                let byNatureRaw = firstNonEmpty(str("bynature"), str("by_nature"))
                var pharmActivityRaw = firstNonEmpty(str("pharmactivity"), str("pharm_activity"))
                var physicalStateRaw = firstNonEmpty(str("physicalstate"), str("physical_state"))

                // Defensive fallback for malformed rows: if physical state lands in ByNature column.
                if isBoolLike(physicalStateRaw), !byNatureRaw.isEmpty, !isBoolLike(byNatureRaw) {
                    physicalStateRaw = byNatureRaw
                }
                // Some rows keep a generic physical-state tag and place detailed organoleptic text in ByNature.
                if isGenericPhysicalStateTag(physicalStateRaw), looksLikeDetailedPhysicalDescription(byNatureRaw) {
                    physicalStateRaw = byNatureRaw
                }
                // Defensive fallback for malformed rows: if activity lands in ByComposition column.
                if isBoolLike(pharmActivityRaw), !byCompositionRaw.isEmpty, !isBoolLike(byCompositionRaw) {
                    pharmActivityRaw = byCompositionRaw
                }

                pharmActivity = pharmActivityRaw.isEmpty ? nil : pharmActivityRaw
                physicalState = physicalStateRaw.isEmpty ? nil : physicalStateRaw
                listB = Self.detectListBFlag(
                    explicitFlag: toBoolFlag(str("list_b")),
                    refType: type,
                    pharmActivity: pharmActivity,
                    storage: storage,
                    ointmentNote: ointmentNote
                )

                let pm = str("prepmethod")
                var prep = pm
                if prep.isEmpty { prep = processNoteRaw }
                if !instructionIdRaw.isEmpty, !prep.lowercased().contains(instructionIdRaw.lowercased()) {
                    prep = prep.isEmpty ? instructionIdRaw : "\(prep); \(instructionIdRaw)"
                }
                if !solubilitySpeedRaw.isEmpty, !prep.lowercased().contains(solubilitySpeedRaw.lowercased()) {
                    prep = prep.isEmpty ? solubilitySpeedRaw : "\(prep); \(solubilitySpeedRaw)"
                }
                if !methodTypeRaw.isEmpty, !prep.lowercased().contains("method_type") {
                    prep = prep.isEmpty ? "Method_Type=\(methodTypeRaw)" : "\(prep); Method_Type=\(methodTypeRaw)"
                }
                func appendMarker(_ base: inout String, key: String, value: String) {
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty else { return }
                    let marker = "\(key)=\(normalized)"
                    if base.lowercased().contains(marker.lowercased()) { return }
                    base = base.isEmpty ? marker : "\(base); \(marker)"
                }
                appendMarker(&prep, key: "Instruction_ID", value: instructionIdRaw)
                appendMarker(&prep, key: "Process_Note", value: processNoteRaw)
                appendMarker(&prep, key: "Solubility_Speed", value: solubilitySpeedRaw)
                appendMarker(&prep, key: "Method_Type", value: methodTypeRaw)
                appendMarker(&prep, key: "Filter_Type", value: filterTypeRaw)
                if toBoolFlag(needsIsotonizationRaw) {
                    appendMarker(&prep, key: "Needs_Isotonization", value: "Yes")
                } else {
                    appendMarker(&prep, key: "Needs_Isotonization", value: needsIsotonizationRaw)
                }
                prepMethod = prep.isEmpty ? nil : prep
                let hr = str("herbalratio")
                herbalRatio = hr.isEmpty ? nil : hr
                var resolvedWaterTempC = num("watertempc") ?? num("water_temp_c")
                if resolvedWaterTempC == nil {
                    let heatMarkersHay = "\(instructionIdRaw) \(processNoteRaw) \(solubilitySpeedRaw)".lowercased()
                    if heatMarkersHay.contains("heat_water_80c")
                        || heatMarkersHay.contains("hot")
                        || heatMarkersHay.contains("гаряч")
                    {
                        resolvedWaterTempC = 80
                    }
                }
                waterTempC = resolvedWaterTempC
                heatBathMin = idx("heatbathmin").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil } ?? (idx("heat_bath_min").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil })
                standMin = idx("standmin").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil } ?? (idx("stand_min").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil })
                coolMin = idx("coolmin").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil } ?? (idx("cool_min").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil })
                strain = toBoolFlag(str("strain"))
                pressMarc = toBoolFlag(str("pressmarc")) || toBoolFlag(str("press_marc"))
                bringToVolume = toBoolFlag(str("bringtovolume")) || toBoolFlag(str("bring_to_volume"))
                shelfLifeHours = idx("shelflifehours").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil } ?? (idx("shelf_life_hours").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil })
                let sp = str("storageprepared")
                storagePrepared = sp.isEmpty ? nil : sp

                let es = str("extractionsolvent")
                extractionSolvent = es.isEmpty ? nil : es
                let tr = str("tinctureratio")
                tinctureRatio = tr.isEmpty ? nil : tr
                macerationDays = idx("macerationdays").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil } ?? (idx("maceration_days").flatMap { $0 < r.count ? toOptionalInt(r[$0]) : nil })
                shakeDaily = toBoolFlag(str("shakedaily")) || toBoolFlag(str("shake_daily"))
                filter = toBoolFlag(str("filter"))
                let stt = str("storagetincture")
                storageTincture = stt.isEmpty ? nil : stt

                let et = str("extracttype")
                extractType = et.isEmpty ? nil : et
                let esol = str("extractsolvent")
                extractSolvent = esol.isEmpty ? nil : esol
                let er = str("extractratio")
                extractRatio = er.isEmpty ? nil : er

                bufferPH = num("bufferph") ?? num("buffer_ph")
                bufferMolarity = num("buffermolarity") ?? num("buffer_molarity")
                let svt = str("solventtype")
                solventType = svt.isEmpty || isBoolLike(svt) ? nil : svt
                let rawSterile = str("sterile")
                sterile = toBoolFlag(rawSterile)
                if prepMethod == nil,
                   !rawSterile.isEmpty,
                   !isBoolLike(rawSterile),
                   (interactionNotes?.lowercased().contains("essentialoilvolatility") == true
                        || rawSterile.contains("1:1000")
                        || rawSterile.contains("1/1000")) {
                    prepMethod = rawSterile
                }
                if solventType == nil,
                   prepMethod?.lowercased().contains("1:1000") == true {
                    solventType = "Water"
                }

                let dt = str("dissolutiontype").isEmpty ? str("dissolution_type") : str("dissolutiontype")
                let dtKey = dt.trimmingCharacters(in: .whitespacesAndNewlines)
                dissolutionType = dtKey.isEmpty ? nil : DissolutionType(rawValue: dtKey)
            } else {
                // Legacy positional: nom, gen, type, vrd, vsd, [kuo], [kv]
                if r.count < 5 { continue }
                nom = cleaned(r[0])
                gen = cleaned(r[1])
                nameRuRef = nil
                type = Self.normalizeReferenceType(cleaned(r[2]))
                isColoring = false
                vrd = toOptionalDouble(r[3])
                vsd = toOptionalDouble(r[4])
                pedsVrd = nil
                pedsRd = nil
                vrdChild0_1 = nil
                vrdChild1_6 = nil
                vrdChild7_14 = nil
                kuo = (r.count > 5) ? toOptionalDouble(r[5]) : nil
                kv = (r.count > 6) ? toOptionalDouble(r[6]) : nil
                gttsPerMl = nil
                eFactor = nil
                density = nil
                solubility = nil
                storage = nil
                interactionNotes = nil
                ointmentEntryType = nil
                ointmentSolventInnKey = nil
                ointmentRatioSoluteToSolvent = nil
                ointmentNote = nil
                needsTrituration = false
                listA = false
                listB = false
                isNarcotic = false
                pharmActivity = nil
                physicalState = nil

                prepMethod = nil
                herbalRatio = nil
                waterTempC = nil
                heatBathMin = nil
                standMin = nil
                coolMin = nil
                strain = false
                pressMarc = false
                bringToVolume = false
                shelfLifeHours = nil
                storagePrepared = nil

                extractionSolvent = nil
                tinctureRatio = nil
                macerationDays = nil
                shakeDaily = false
                filter = false
                storageTincture = nil

                extractType = nil
                extractSolvent = nil
                extractRatio = nil

                bufferPH = nil
                bufferMolarity = nil
                solventType = nil
                sterile = false

                dissolutionType = nil
            }

            if nom.isEmpty || gen.isEmpty || type.isEmpty { continue }
            let nomKey = nom
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if nomKey.isEmpty || seenNomKeys.contains(nomKey) { continue }
            seenNomKeys.insert(nomKey)

            try sqlite.execute(
                sql: """
                INSERT INTO extemp_reference_substances(
                  name_lat_nom,
                  name_lat_gen,
                  name_ru_ref,
                  type,
                  is_coloring,
                  vrd_g,
                  vsd_g,
                  peds_vrd_g,
                  peds_rd_g,
                  vrd_child_0_1,
                  vrd_child_1_6,
                  vrd_child_7_14,
                  kuo_ml_per_g,
                  kv_g_per_100g,
                  gtts_per_ml,
                  e_factor,
                  density,
                  solubility,
                  storage,
                  interaction_notes,
                  ointment_entry_type,
                  ointment_solvent_inn_key,
                  ointment_ratio_solute_to_solvent,
                  ointment_note,
                  needs_trituration,
                  list_a,
                  list_b,
                  is_narcotic,
                  pharm_activity,
                  physical_state,

                  prep_method,
                  herbal_ratio,
                  water_temp_c,
                  heat_bath_min,
                  stand_min,
                  cool_min,
                  strain,
                  press_marc,
                  bring_to_volume,
                  shelf_life_hours,
                  storage_prepared,

                  extraction_solvent,
                  tincture_ratio,
                  maceration_days,
                  shake_daily,
                  filter,
                  storage_tincture,

                  extract_type,
                  extract_solvent,
                  extract_ratio,

                  buffer_ph,
                  buffer_molarity,
                  solvent_type,
                  sterile,
                  dissolution_type,
                  source
                )
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(name_lat_nom) DO UPDATE SET
                  name_lat_gen = excluded.name_lat_gen,
                  name_ru_ref = excluded.name_ru_ref,
                  type = excluded.type,
                  vrd_g = excluded.vrd_g,
                  vsd_g = excluded.vsd_g,
                  peds_vrd_g = excluded.peds_vrd_g,
                  peds_rd_g = excluded.peds_rd_g,
                  vrd_child_0_1 = excluded.vrd_child_0_1,
                  vrd_child_1_6 = excluded.vrd_child_1_6,
                  vrd_child_7_14 = excluded.vrd_child_7_14,
                  kuo_ml_per_g = excluded.kuo_ml_per_g,
                  kv_g_per_100g = excluded.kv_g_per_100g,
                  gtts_per_ml = excluded.gtts_per_ml,
                  e_factor = excluded.e_factor,
                  density = excluded.density,
                  solubility = excluded.solubility,
                  storage = excluded.storage,
                  interaction_notes = excluded.interaction_notes,
                  ointment_entry_type = excluded.ointment_entry_type,
                  ointment_solvent_inn_key = excluded.ointment_solvent_inn_key,
                  ointment_ratio_solute_to_solvent = excluded.ointment_ratio_solute_to_solvent,
                  ointment_note = excluded.ointment_note,
                  needs_trituration = excluded.needs_trituration,
                  list_a = excluded.list_a,
                  list_b = excluded.list_b,
                  is_narcotic = excluded.is_narcotic,
                  pharm_activity = excluded.pharm_activity,
                  physical_state = excluded.physical_state,

                  prep_method = excluded.prep_method,
                  herbal_ratio = excluded.herbal_ratio,
                  water_temp_c = excluded.water_temp_c,
                  heat_bath_min = excluded.heat_bath_min,
                  stand_min = excluded.stand_min,
                  cool_min = excluded.cool_min,
                  strain = excluded.strain,
                  press_marc = excluded.press_marc,
                  bring_to_volume = excluded.bring_to_volume,
                  shelf_life_hours = excluded.shelf_life_hours,
                  storage_prepared = excluded.storage_prepared,

                  extraction_solvent = excluded.extraction_solvent,
                  tincture_ratio = excluded.tincture_ratio,
                  maceration_days = excluded.maceration_days,
                  shake_daily = excluded.shake_daily,
                  filter = excluded.filter,
                  storage_tincture = excluded.storage_tincture,

                  extract_type = excluded.extract_type,
                  extract_solvent = excluded.extract_solvent,
                  extract_ratio = excluded.extract_ratio,

                  buffer_ph = excluded.buffer_ph,
                  buffer_molarity = excluded.buffer_molarity,
                  solvent_type = excluded.solvent_type,
                  sterile = excluded.sterile,
                  dissolution_type = excluded.dissolution_type,
                  source = excluded.source;
                """,
                binds: [
                    .text(nom),
                    .text(gen),
                    nameRuRef == nil ? .null : .text(nameRuRef!),
                    .text(type),
                    .int(Int64(isColoring ? 1 : 0)),
                    vrd == nil ? .null : .double(vrd!),
                    vsd == nil ? .null : .double(vsd!),
                    pedsVrd == nil ? .null : .double(pedsVrd!),
                    pedsRd == nil ? .null : .double(pedsRd!),
                    vrdChild0_1 == nil ? .null : .double(vrdChild0_1!),
                    vrdChild1_6 == nil ? .null : .double(vrdChild1_6!),
                    vrdChild7_14 == nil ? .null : .double(vrdChild7_14!),
                    kuo == nil ? .null : .double(kuo!),
                    kv == nil ? .null : .double(kv!),
                    gttsPerMl == nil ? .null : .double(gttsPerMl!),
                    eFactor == nil ? .null : .double(eFactor!),
                    density == nil ? .null : .double(density!),
                    solubility == nil ? .null : .text(solubility!),
                    storage == nil ? .null : .text(storage!),
                    interactionNotes == nil ? .null : .text(interactionNotes!),
                    ointmentEntryType == nil ? .null : .text(ointmentEntryType!),
                    ointmentSolventInnKey == nil ? .null : .text(ointmentSolventInnKey!),
                    ointmentRatioSoluteToSolvent == nil ? .null : .double(ointmentRatioSoluteToSolvent!),
                    ointmentNote == nil ? .null : .text(ointmentNote!),
                    .int(Int64(needsTrituration ? 1 : 0)),
                    .int(Int64(listA ? 1 : 0)),
                    .int(Int64(listB ? 1 : 0)),
                    .int(Int64(isNarcotic ? 1 : 0)),
                    pharmActivity == nil ? .null : .text(pharmActivity!),
                    physicalState == nil ? .null : .text(physicalState!),

                    prepMethod == nil ? .null : .text(prepMethod!),
                    herbalRatio == nil ? .null : .text(herbalRatio!),
                    waterTempC == nil ? .null : .double(waterTempC!),
                    heatBathMin == nil ? .null : .int(Int64(heatBathMin!)),
                    standMin == nil ? .null : .int(Int64(standMin!)),
                    coolMin == nil ? .null : .int(Int64(coolMin!)),
                    .int(Int64(strain ? 1 : 0)),
                    .int(Int64(pressMarc ? 1 : 0)),
                    .int(Int64(bringToVolume ? 1 : 0)),
                    shelfLifeHours == nil ? .null : .int(Int64(shelfLifeHours!)),
                    storagePrepared == nil ? .null : .text(storagePrepared!),

                    extractionSolvent == nil ? .null : .text(extractionSolvent!),
                    tinctureRatio == nil ? .null : .text(tinctureRatio!),
                    macerationDays == nil ? .null : .int(Int64(macerationDays!)),
                    .int(Int64(shakeDaily ? 1 : 0)),
                    .int(Int64(filter ? 1 : 0)),
                    storageTincture == nil ? .null : .text(storageTincture!),

                    extractType == nil ? .null : .text(extractType!),
                    extractSolvent == nil ? .null : .text(extractSolvent!),
                    extractRatio == nil ? .null : .text(extractRatio!),

                    bufferPH == nil ? .null : .double(bufferPH!),
                    bufferMolarity == nil ? .null : .double(bufferMolarity!),
                    solventType == nil ? .null : .text(solventType!),
                    .int(Int64(sterile ? 1 : 0)),
                    dissolutionType == nil ? .null : .text(dissolutionType!.rawValue),
                    .text("extemp_reference_200.csv")
                ]
            )
        }
    }

    private func ensureSolventProfilesImport() throws {
        guard let csvUrl = Bundle.main.url(forResource: "solvent_profiles", withExtension: "csv") else {
            return
        }

        let csv = (try? String(contentsOf: csvUrl, encoding: .utf8)) ?? ""
        if csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        let parsed = parseCsvWithHeader(csv)
        let headerIndex: [String: Int] = {
            var out: [String: Int] = [:]
            for (index, header) in parsed.header.enumerated() {
                let key = header
                    .replacingOccurrences(of: "\u{feff}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if !key.isEmpty, out[key] == nil {
                    out[key] = index
                }
            }
            return out
        }()

        func idx(_ key: String) -> Int? {
            headerIndex[key.lowercased()]
        }

        func str(_ row: [String], _ key: String) -> String {
            guard let index = idx(key), index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func optionalString(_ row: [String], _ key: String) -> String? {
            let value = str(row, key)
            return value.isEmpty ? nil : value
        }

        func optionalDouble(_ row: [String], _ key: String) -> Double? {
            let value = str(row, key)
            if value.isEmpty || value == "-" { return nil }
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }

        func optionalInt(_ row: [String], _ key: String) -> Int? {
            let value = str(row, key)
            if value.isEmpty || value == "-" { return nil }
            if let intValue = Int(value) { return intValue }
            if let doubleValue = Double(value.replacingOccurrences(of: ",", with: ".")) {
                return Int(doubleValue.rounded())
            }
            return nil
        }

        func boolValue(_ row: [String], _ key: String) -> Bool {
            let value = str(row, key).lowercased()
            switch value {
            case "1", "true", "yes", "y", "так", "да", "+":
                return true
            default:
                return false
            }
        }

        for row in parsed.rows {
            let nameLatNom = str(row, "name_lat_nom")
            let nameLatGen = str(row, "name_lat_gen")
            let type = str(row, "type")
            if nameLatNom.isEmpty || nameLatGen.isEmpty || type.isEmpty { continue }

            let density = optionalDouble(row, "density")
            let solventType = optionalString(row, "solvent_type")
            let isVolatile = boolValue(row, "is_volatile")
            let isFlammable = boolValue(row, "is_flammable")
            let heatingAllowed = optionalString(row, "heating_allowed")
            let heatingTempMaxC = optionalDouble(row, "heating_temp_max_c")
            let defaultEthanolStrength = optionalInt(row, "default_ethanol_strength")
            let incompatibleWithEthanol = boolValue(row, "incompatible_with_ethanol")
            let physicalState = optionalString(row, "physical_state")
            let storage = optionalString(row, "storage")
            let interactionNotes = optionalString(row, "interaction_notes")

            try sqlite.execute(
                sql: """
                INSERT INTO extemp_reference_substances(
                  name_lat_nom,
                  name_lat_gen,
                  type,
                  density,
                  storage,
                  interaction_notes,
                  physical_state,
                  solvent_type,
                  is_volatile,
                  is_flammable,
                  heating_allowed,
                  heating_temp_max_c,
                  default_ethanol_strength,
                  incompatible_with_ethanol,
                  source
                )
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(name_lat_nom) DO UPDATE SET
                  name_lat_gen = excluded.name_lat_gen,
                  type = excluded.type,
                  density = excluded.density,
                  storage = excluded.storage,
                  interaction_notes = excluded.interaction_notes,
                  physical_state = excluded.physical_state,
                  solvent_type = excluded.solvent_type,
                  is_volatile = excluded.is_volatile,
                  is_flammable = excluded.is_flammable,
                  heating_allowed = excluded.heating_allowed,
                  heating_temp_max_c = excluded.heating_temp_max_c,
                  default_ethanol_strength = excluded.default_ethanol_strength,
                  incompatible_with_ethanol = excluded.incompatible_with_ethanol,
                  source = excluded.source;
                """,
                binds: [
                    .text(nameLatNom),
                    .text(nameLatGen),
                    .text(type),
                    density == nil ? .null : .double(density!),
                    storage == nil ? .null : .text(storage!),
                    interactionNotes == nil ? .null : .text(interactionNotes!),
                    physicalState == nil ? .null : .text(physicalState!),
                    solventType == nil ? .null : .text(solventType!),
                    .int(Int64(isVolatile ? 1 : 0)),
                    .int(Int64(isFlammable ? 1 : 0)),
                    heatingAllowed == nil ? .null : .text(heatingAllowed!),
                    heatingTempMaxC == nil ? .null : .double(heatingTempMaxC!),
                    defaultEthanolStrength == nil ? .null : .int(Int64(defaultEthanolStrength!)),
                    .int(Int64(incompatibleWithEthanol ? 1 : 0)),
                    .text("solvent_profiles.csv")
                ]
            )
        }
    }

    private func parseSimpleCsv(_ content: String) -> [[String]] {
        return parseCsvWithHeader(content).rows
    }

    private func parseCsvWithHeader(_ content: String) -> (header: [String], rows: [[String]]) {
        func parseLine(_ line: String) -> [String] {
            var out: [String] = []
            out.reserveCapacity(12)
            var cur = ""
            var inQuotes = false

            let chars = Array(line)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if ch == "\"" {
                    if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                        cur.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes.toggle()
                    i += 1
                    continue
                }

                if ch == "," && !inQuotes {
                    out.append(cur)
                    cur = ""
                    i += 1
                    continue
                }

                cur.append(ch)
                i += 1
            }

            out.append(cur)
            return out
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        guard let first = lines.first else { return (header: [], rows: []) }
        let header = parseLine(first)

        var rows: [[String]] = []
        rows.reserveCapacity(max(0, lines.count - 1))
        if lines.count <= 1 { return (header: header, rows: []) }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            var cols = parseLine(trimmed)
            if cols.count > header.count {
                let extra = cols[header.count...]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if extra.contains(where: { !$0.isEmpty }) {
                    // Skip malformed rows with non-empty overflow columns.
                    continue
                }
                cols = Array(cols.prefix(header.count))
            } else if cols.count < header.count {
                cols.append(contentsOf: Array(repeating: "", count: header.count - cols.count))
            }
            if cols.count >= 3 {
                let c0 = cols[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let c1 = cols[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let c2 = cols[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let isHeaderSnake = (c0 == "name_lat_nom" && c1 == "name_lat_gen" && c2 == "type")
                let isHeaderCamel = (c0 == "namelatnom" && c1 == "namelatgen" && c2 == "type")
                let isHeaderWithNumberColumn = (c0 == "№" || c0 == "no" || c0 == "number")
                if isHeaderSnake || isHeaderCamel || isHeaderWithNumberColumn {
                    continue
                }
            }
            rows.append(cols)
        }
        return (header: header, rows: rows)
    }

    private func ensureIncompatibilitiesSchema() throws {
        try sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS incompatibilities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                a_key TEXT NOT NULL,
                b_key TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT NOT NULL,
                source TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            );
            """
        )
        try sqlite.execute(
            sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_incompatibilities_pair
            ON incompatibilities(a_key, b_key);
            """
        )

        // Seed: Kalii permanganas + Glycerinum (oxidizer + reducer)
        // Store in canonical order to ensure uniqueness.
        try upsertIncompatibilityPair(
            aKey: "kalii permanganas",
            bKey: "glycerinum",
            severity: "block",
            message: "Калия перманганат несовместим с Глицерином (взрывоопасно: окисление).",
            source: "seed"
        )

        let iodineResorcinPairs: [(String, String)] = [
            ("iodum", "resorcinum"),
            ("iodium", "resorcinum"),
            ("iodine", "resorcinol"),
            ("ref:iodum", "ref:resorcinum"),
            ("ref:iodium", "ref:resorcinum"),
            ("ref:iodine", "ref:resorcinol")
        ]
        for (aKey, bKey) in iodineResorcinPairs {
            try upsertIncompatibilityPair(
                aKey: aKey,
                bKey: bKey,
                severity: "block",
                message: "Йод и резорцин несовместимы: происходит йодирование резорцина, раствор обесцвечивается и/или может выпадать осадок.",
                source: "seed"
            )
        }
    }

    private func upsertIncompatibilityPair(
        aKey: String,
        bKey: String,
        severity: String,
        message: String,
        source: String?
    ) throws {
        let a = aKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = bKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if a.isEmpty || b.isEmpty { return }
        let ordered = [a, b].sorted()

        try sqlite.execute(
            sql: """
            INSERT INTO incompatibilities(a_key, b_key, severity, message, source)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(a_key, b_key) DO UPDATE SET
              severity = excluded.severity,
              message = excluded.message,
              source = excluded.source;
            """,
            binds: [
                .text(ordered[0]),
                .text(ordered[1]),
                .text(severity),
                .text(message),
                source == nil ? .null : .text(source!)
            ]
        )
    }

    func checkHardIncompatibility(new: ExtempSubstance, existing: [ExtempIngredientDraft]) async throws -> (severity: String, message: String)? {
        let newKey = ExtempRepository.normKey(new)
        if newKey.isEmpty { return nil }

        let existingKeys = existing.map { ExtempRepository.normKey($0.substance) }.filter { !$0.isEmpty }
        if existingKeys.isEmpty { return nil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(severity: String, message: String)?, Error>) in
            queue.async(execute: DispatchWorkItem {
                do {
                    for k in existingKeys {
                        let ordered = [newKey, k].sorted()
                        let row = try self.sqlite.querySingleRow(
                            sql: """
                            SELECT severity, message
                            FROM incompatibilities
                            WHERE a_key = ? AND b_key = ?
                            LIMIT 1;
                            """,
                            binds: [.text(ordered[0]), .text(ordered[1])]
                        )

                        let severity = ((row?["severity"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = ((row?["message"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !severity.isEmpty, !message.isEmpty {
                            continuation.resume(returning: (severity: severity, message: message))
                            return
                        }
                    }
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    private static func normKey(_ s: ExtempSubstance) -> String {
        let raw = s.innKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw.lowercased() }
        return s.nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func searchSubstances(query: String, limit: Int = 30) async throws -> [ExtempSubstance] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ExtempSubstance], Error>) in
            let workItem = DispatchWorkItem {
                do {
                    let likeRaw = "%" + q + "%"
                    let likeLower = "%" + q.lowercased() + "%"
                    let likeUpper = "%" + q.uppercased() + "%"
                    let likeFirstUpper: String = {
                        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let first = trimmed.first else { return likeRaw }
                        let firstUp = String(first).uppercased()
                        let rest = String(trimmed.dropFirst())
                        return "%" + (firstUp + rest) + "%"
                    }()
                    let sql: String = """
                        SELECT * FROM (
                          SELECT
                            COALESCE(s.id, -r.id) AS id,
                            COALESCE(s.inn_key, ('ref:' || r.name_lat_nom)) AS inn_key,
                            COALESCE(s.category_id, 0) AS category_id,
                            COALESCE(NULLIF(trim(s.name_ru), ''), NULLIF(trim(r.name_ru_ref), ''), r.name_lat_nom) AS name_ru,
                            r.name_lat_nom AS name_lat_nom,
                            r.name_lat_gen AS name_lat_gen,
                            COALESCE(s.role, 'Ref') AS role,
                            r.type AS ref_type,
                            r.is_coloring AS is_coloring,
                            r.vrd_g AS vrd_g,
                            r.vsd_g AS vsd_g,
                            r.peds_vrd_g AS peds_vrd_g,
                            r.peds_rd_g AS peds_rd_g,
                            r.vrd_child_0_1 AS vrd_child_0_1,
                            r.vrd_child_1_6 AS vrd_child_1_6,
                            r.vrd_child_7_14 AS vrd_child_7_14,
                            r.kuo_ml_per_g AS kuo_ml_per_g,
                            r.kv_g_per_100g AS kv_g_per_100g,
                            r.gtts_per_ml AS gtts_per_ml,
                            r.e_factor AS e_factor,
                            r.density AS density,
                            r.solubility AS solubility,
                            r.storage AS storage,
                            r.interaction_notes AS interaction_notes,
                            r.ointment_entry_type AS ointment_entry_type,
                            r.ointment_solvent_inn_key AS ointment_solvent_inn_key,
                            r.ointment_ratio_solute_to_solvent AS ointment_ratio_solute_to_solvent,
                            r.ointment_note AS ointment_note,
                            COALESCE(r.needs_trituration, 0) AS needs_trituration,
                            COALESCE(r.list_a, 0) AS list_a,
                            COALESCE(r.list_b, 0) AS list_b,
                            COALESCE(r.is_narcotic, 0) AS is_narcotic,
                            r.pharm_activity AS pharm_activity,
                            r.physical_state AS physical_state,
                            r.prep_method AS prep_method,
                            r.herbal_ratio AS herbal_ratio,
                            r.water_temp_c AS water_temp_c,
                            r.heat_bath_min AS heat_bath_min,
                            r.stand_min AS stand_min,
                            r.cool_min AS cool_min,
                            COALESCE(r.strain, 0) AS strain,
                            COALESCE(r.press_marc, 0) AS press_marc,
                            COALESCE(r.bring_to_volume, 0) AS bring_to_volume,
                            r.shelf_life_hours AS shelf_life_hours,
                            r.storage_prepared AS storage_prepared,
                            r.extraction_solvent AS extraction_solvent,
                            r.tincture_ratio AS tincture_ratio,
                            r.maceration_days AS maceration_days,
                            COALESCE(r.shake_daily, 0) AS shake_daily,
                            COALESCE(r.filter, 0) AS filter,
                            r.storage_tincture AS storage_tincture,
                            r.extract_type AS extract_type,
                            r.extract_solvent AS extract_solvent,
                            r.extract_ratio AS extract_ratio,
                            r.buffer_ph AS buffer_ph,
                            r.buffer_molarity AS buffer_molarity,
                            r.solvent_type AS solvent_type,
                            COALESCE(r.sterile, 0) AS sterile,
                            r.is_volatile AS is_volatile,
                            r.is_flammable AS is_flammable,
                            r.heating_allowed AS heating_allowed,
                            r.heating_temp_max_c AS heating_temp_max_c,
                            r.default_ethanol_strength AS default_ethanol_strength,
                            r.incompatible_with_ethanol AS incompatible_with_ethanol,
                            r.dissolution_type AS dissolution_type
                          FROM extemp_reference_substances r
                          LEFT JOIN substances s
                            ON lower(s.name_lat_nom) = lower(r.name_lat_nom)
                          WHERE (
                            (s.name_ru LIKE ? OR s.name_ru LIKE ? OR s.name_ru LIKE ? OR s.name_ru LIKE ?)
                            OR (r.name_ru_ref LIKE ? OR r.name_ru_ref LIKE ? OR r.name_ru_ref LIKE ? OR r.name_ru_ref LIKE ?)
                            OR lower(r.name_lat_nom) LIKE ?
                            OR lower(r.name_lat_gen) LIKE ?
                            OR lower(r.type) LIKE ?
                            OR lower(COALESCE(s.inn_key, '')) LIKE ?
                          )

                          UNION ALL

                          SELECT
                            s.id AS id,
                            s.inn_key AS inn_key,
                            s.category_id AS category_id,
                            s.name_ru AS name_ru,
                            s.name_lat_nom AS name_lat_nom,
                            s.name_lat_gen AS name_lat_gen,
                            s.role AS role,
                            '' AS ref_type,
                            0 AS is_coloring,
                            NULL AS vrd_g,
                            NULL AS vsd_g,
                            NULL AS peds_vrd_g,
                            NULL AS peds_rd_g,
                            NULL AS vrd_child_0_1,
                            NULL AS vrd_child_1_6,
                            NULL AS vrd_child_7_14,
                            NULL AS kuo_ml_per_g,
                            NULL AS kv_g_per_100g,
                            NULL AS gtts_per_ml,
                            NULL AS e_factor,
                            NULL AS density,
                            NULL AS solubility,
                            NULL AS storage,
                            NULL AS interaction_notes,
                            NULL AS ointment_entry_type,
                            NULL AS ointment_solvent_inn_key,
                            NULL AS ointment_ratio_solute_to_solvent,
                            NULL AS ointment_note,
                            0 AS needs_trituration,
                            0 AS list_a,
                            0 AS list_b,
                            0 AS is_narcotic,
                            NULL AS pharm_activity,
                            NULL AS physical_state,
                            NULL AS prep_method,
                            NULL AS herbal_ratio,
                            NULL AS water_temp_c,
                            NULL AS heat_bath_min,
                            NULL AS stand_min,
                            NULL AS cool_min,
                            0 AS strain,
                            0 AS press_marc,
                            0 AS bring_to_volume,
                            NULL AS shelf_life_hours,
                            NULL AS storage_prepared,
                            NULL AS extraction_solvent,
                            NULL AS tincture_ratio,
                            NULL AS maceration_days,
                            0 AS shake_daily,
                            0 AS filter,
                            NULL AS storage_tincture,
                            NULL AS extract_type,
                            NULL AS extract_solvent,
                            NULL AS extract_ratio,
                            NULL AS buffer_ph,
                            NULL AS buffer_molarity,
                            NULL AS solvent_type,
                            0 AS sterile,
                            NULL AS is_volatile,
                            NULL AS is_flammable,
                            NULL AS heating_allowed,
                            NULL AS heating_temp_max_c,
                            NULL AS default_ethanol_strength,
                            NULL AS incompatible_with_ethanol,
                            NULL AS dissolution_type
                          FROM substances s
                          LEFT JOIN extemp_reference_substances r
                            ON lower(r.name_lat_nom) = lower(s.name_lat_nom)
                          WHERE s.is_active = 1
                            AND r.id IS NULL
                            AND (
                              s.name_ru LIKE ?
                              OR s.name_ru LIKE ?
                              OR s.name_ru LIKE ?
                              OR s.name_ru LIKE ?
                              OR lower(s.name_lat_nom) LIKE ?
                              OR lower(s.name_lat_gen) LIKE ?
                              OR lower(s.inn_key) LIKE ?
                            )
                        )
                        ORDER BY name_ru ASC
                        LIMIT ?;
                        """
                    let binds: [SQLiteValue] = [
                        .text(likeRaw),
                        .text(likeFirstUpper),
                        .text(likeUpper),
                        .text(likeLower),
                        .text(likeRaw),
                        .text(likeFirstUpper),
                        .text(likeUpper),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeRaw),
                        .text(likeFirstUpper),
                        .text(likeUpper),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeLower),
                        .text(likeLower),
                        .int(Int64(limit))
                    ]
                    let rows: [[String: String?]] = try self.sqlite.queryRows(sql: sql, binds: binds)

                    let out: [ExtempSubstance] = rows.compactMap { r -> ExtempSubstance? in
                        let id = Int((r["id"] ?? nil) ?? "")
                        let innKey = ((r["inn_key"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let categoryId = Int((r["category_id"] ?? nil) ?? "")
                        let nameRu = ((r["name_ru"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameLatNom = ((r["name_lat_nom"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameLatGen = ((r["name_lat_gen"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let role = ((r["role"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let refType = Self.normalizeReferenceType(((r["ref_type"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))

                        let isColoring = ((r["is_coloring"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"

                        let vrdG = Double(((r["vrd_g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let vsdG = Double(((r["vsd_g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let pedsVrdG = Double(((r["peds_vrd_g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let pedsRdG = Double(((r["peds_rd_g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let vrdChild0_1 = Double(((r["vrd_child_0_1"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let vrdChild1_6 = Double(((r["vrd_child_1_6"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let vrdChild7_14 = Double(((r["vrd_child_7_14"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let kuoMlPerG = Double(((r["kuo_ml_per_g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let kvGPer100G = Double(((r["kv_g_per_100g"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let gttsPerMl = Double(((r["gtts_per_ml"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let eFactor = Double(((r["e_factor"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let density = Double(((r["density"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")

                        let solubility = ((r["solubility"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let storage = ((r["storage"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let interactionNotes = ((r["interaction_notes"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)

                        let ointmentEntryType = ((r["ointment_entry_type"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ointmentSolventInnKey = ((r["ointment_solvent_inn_key"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ointmentRatioSoluteToSolvent = Double(((r["ointment_ratio_solute_to_solvent"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let ointmentNote = ((r["ointment_note"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)

                        let needsTrituration = ((r["needs_trituration"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let listA = ((r["list_a"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let listBStored = ((r["list_b"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let isNarcotic = ((r["is_narcotic"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let pharmActivity = ((r["pharm_activity"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let physicalState = ((r["physical_state"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let listB = Self.detectListBFlag(
                            explicitFlag: listBStored,
                            refType: refType,
                            pharmActivity: pharmActivity,
                            storage: storage,
                            ointmentNote: ointmentNote
                        )

                        let prepMethod = ((r["prep_method"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let herbalRatio = ((r["herbal_ratio"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let waterTempC = Double(((r["water_temp_c"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let heatBathMin = Int((r["heat_bath_min"] ?? nil) ?? "")
                        let standMin = Int((r["stand_min"] ?? nil) ?? "")
                        let coolMin = Int((r["cool_min"] ?? nil) ?? "")
                        let strain = ((r["strain"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let pressMarc = ((r["press_marc"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let bringToVolume = ((r["bring_to_volume"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let shelfLifeHours = Int((r["shelf_life_hours"] ?? nil) ?? "")
                        let storagePrepared = ((r["storage_prepared"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)

                        let extractionSolvent = ((r["extraction_solvent"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tinctureRatio = ((r["tincture_ratio"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let macerationDays = Int((r["maceration_days"] ?? nil) ?? "")
                        let shakeDaily = ((r["shake_daily"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let filter = ((r["filter"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let storageTincture = ((r["storage_tincture"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)

                        let extractType = ((r["extract_type"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let extractSolvent = ((r["extract_solvent"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let extractRatio = ((r["extract_ratio"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)

                        let bufferPH = Double(((r["buffer_ph"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let bufferMolarity = Double(((r["buffer_molarity"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let solventType = ((r["solvent_type"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let sterile = ((r["sterile"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                        let isVolatile: Bool? = {
                            let raw = ((r["is_volatile"] ?? nil) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty { return nil }
                            return raw == "1"
                        }()
                        let isFlammable: Bool? = {
                            let raw = ((r["is_flammable"] ?? nil) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty { return nil }
                            return raw == "1"
                        }()
                        let heatingAllowed: NonAqueousHeatingAllowance? = {
                            let raw = ((r["heating_allowed"] ?? nil) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty { return nil }
                            return NonAqueousHeatingAllowance(rawValue: raw)
                        }()
                        let heatingTempMaxC = Double(((r["heating_temp_max_c"] ?? nil) ?? "")?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".") ?? "")
                        let defaultEthanolStrength = Int((r["default_ethanol_strength"] ?? nil) ?? "")
                        let incompatibleWithEthanol: Bool? = {
                            let raw = ((r["incompatible_with_ethanol"] ?? nil) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty { return nil }
                            return raw == "1"
                        }()

                        let dissolutionType: DissolutionType? = {
                            let raw = ((r["dissolution_type"] ?? nil) ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty { return nil }
                            return DissolutionType(rawValue: raw)
                        }()

                        let mergedReference = SubstancePropertyCatalog.mergedReferenceValues(
                            innKey: innKey,
                            nameLatNom: nameLatNom,
                            nameRu: nameRu,
                            solubility: (solubility?.isEmpty ?? true) ? nil : solubility,
                            kuoMlPerG: kuoMlPerG,
                            storage: (storage?.isEmpty ?? true) ? nil : storage,
                            interactionNotes: (interactionNotes?.isEmpty ?? true) ? nil : interactionNotes,
                            vrdG: vrdG,
                            vsdG: vsdG,
                            listA: listA,
                            isNarcotic: isNarcotic
                        )

                        guard let id, let categoryId, !innKey.isEmpty, !nameLatNom.isEmpty else { return nil }
                        return ExtempSubstance(
                            id: id,
                            innKey: innKey,
                            categoryId: categoryId,
                            nameRu: nameRu,
                            nameLatNom: nameLatNom,
                            nameLatGen: nameLatGen,
                            role: role,
                            refType: refType,
                            isColoring: isColoring,
                            vrdG: mergedReference.vrdG,
                            vsdG: mergedReference.vsdG,
                            pedsVrdG: pedsVrdG,
                            pedsRdG: pedsRdG,
                            vrdChild0_1: vrdChild0_1,
                            vrdChild1_6: vrdChild1_6,
                            vrdChild7_14: vrdChild7_14,
                            kuoMlPerG: mergedReference.kuoMlPerG,
                            kvGPer100G: kvGPer100G,
                            gttsPerMl: gttsPerMl,
                            eFactor: eFactor,
                            density: density,
                            solubility: mergedReference.solubility,
                            storage: mergedReference.storage,
                            interactionNotes: mergedReference.interactionNotes,
                            ointmentEntryType: (ointmentEntryType?.isEmpty ?? true) ? nil : ointmentEntryType,
                            ointmentSolventInnKey: (ointmentSolventInnKey?.isEmpty ?? true) ? nil : ointmentSolventInnKey,
                            ointmentRatioSoluteToSolvent: ointmentRatioSoluteToSolvent,
                            ointmentNote: (ointmentNote?.isEmpty ?? true) ? nil : ointmentNote,
                            needsTrituration: needsTrituration,
                            listA: mergedReference.listA,
                            listB: listB,
                            isNarcotic: mergedReference.isNarcotic,
                            pharmActivity: (pharmActivity?.isEmpty ?? true) ? nil : pharmActivity,
                            physicalState: (physicalState?.isEmpty ?? true) ? nil : physicalState,
                            prepMethod: (prepMethod?.isEmpty ?? true) ? nil : prepMethod,
                            herbalRatio: (herbalRatio?.isEmpty ?? true) ? nil : herbalRatio,
                            waterTempC: waterTempC,
                            heatBathMin: heatBathMin,
                            standMin: standMin,
                            coolMin: coolMin,
                            strain: strain,
                            pressMarc: pressMarc,
                            bringToVolume: bringToVolume,
                            shelfLifeHours: shelfLifeHours,
                            storagePrepared: (storagePrepared?.isEmpty ?? true) ? nil : storagePrepared,
                            extractionSolvent: (extractionSolvent?.isEmpty ?? true) ? nil : extractionSolvent,
                            tinctureRatio: (tinctureRatio?.isEmpty ?? true) ? nil : tinctureRatio,
                            macerationDays: macerationDays,
                            shakeDaily: shakeDaily,
                            filter: filter,
                            storageTincture: (storageTincture?.isEmpty ?? true) ? nil : storageTincture,
                            extractType: (extractType?.isEmpty ?? true) ? nil : extractType,
                            extractSolvent: (extractSolvent?.isEmpty ?? true) ? nil : extractSolvent,
                            extractRatio: (extractRatio?.isEmpty ?? true) ? nil : extractRatio,
                            bufferPH: bufferPH,
                            bufferMolarity: bufferMolarity,
                            solventType: (solventType?.isEmpty ?? true) ? nil : solventType,
                            sterile: sterile,
                            isVolatile: isVolatile,
                            isFlammable: isFlammable,
                            heatingAllowed: heatingAllowed,
                            heatingTempMaxC: heatingTempMaxC,
                            defaultEthanolStrength: defaultEthanolStrength,
                            incompatibleWithEthanol: incompatibleWithEthanol,
                            dissolutionType: dissolutionType
                        )
                    }

                    let hidden = LivingDeathEasterEgg.searchMatches(query: q)
                    let merged = LivingDeathEasterEgg.mergeSearchResults(hidden: hidden, db: out, limit: limit)
                    continuation.resume(returning: merged)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            queue.async(execute: workItem)
        }
    }

    func listUnits() async throws -> [ExtempUnit] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ExtempUnit], Error>) in
            queue.async {
                do {
                    let rows = try self.sqlite.queryRows(
                        sql: """
                        SELECT id, code, name_ru, lat
                        FROM unit_codes
                        ORDER BY id ASC;
                        """,
                        binds: []
                    )

                    let out: [ExtempUnit] = rows.compactMap { r in
                        let id = Int((r["id"] ?? nil) ?? "")
                        let code = ((r["code"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameRu = ((r["name_ru"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let lat = ((r["lat"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                        guard let id, !code.isEmpty else { return nil }
                        return ExtempUnit(id: id, code: code, nameRu: nameRu, lat: lat)
                    }

                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func listDosageForms() async throws -> [ExtempDosageForm] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ExtempDosageForm], Error>) in
            queue.async {
                do {
                    let rows = try self.sqlite.queryRows(
                        sql: """
                        SELECT id, code, name_ru, COALESCE(lat_mf, '') AS lat_mf
                        FROM dosage_forms
                        ORDER BY id ASC;
                        """,
                        binds: []
                    )

                    let out: [ExtempDosageForm] = rows.compactMap { r in
                        let id = Int((r["id"] ?? nil) ?? "")
                        let code = ((r["code"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameRu = ((r["name_ru"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let latMf = ((r["lat_mf"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                        guard let id, !code.isEmpty else { return nil }
                        return ExtempDosageForm(id: id, code: code, nameRu: nameRu, latMf: latMf)
                    }

                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func listMfRules() async throws -> [ExtempMfRule] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ExtempMfRule], Error>) in
            queue.async {
                do {
                    let rows = try self.sqlite.queryRows(
                        sql: """
                        SELECT id, priority, form_id, rule_name,
                               COALESCE(if_any_role, '') AS if_any_role,
                               COALESCE(if_any_substance_inn_key, '') AS if_any_substance_inn_key
                        FROM mf_rules
                        ORDER BY priority ASC;
                        """,
                        binds: []
                    )

                    let out: [ExtempMfRule] = rows.compactMap { r in
                        let id = Int((r["id"] ?? nil) ?? "")
                        let priority = Int((r["priority"] ?? nil) ?? "")
                        let formId = Int((r["form_id"] ?? nil) ?? "")
                        let ruleName = ((r["rule_name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let ifAnyRole = ((r["if_any_role"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let ifAnySubstanceInnKey = ((r["if_any_substance_inn_key"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                        guard let id, let priority, let formId, !ruleName.isEmpty else { return nil }
                        return ExtempMfRule(
                            id: id,
                            priority: priority,
                            formId: formId,
                            ruleName: ruleName,
                            ifAnyRole: ifAnyRole,
                            ifAnySubstanceInnKey: ifAnySubstanceInnKey
                        )
                    }

                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadStorageRules(substanceId: Int) async throws -> [ExtempStorageRule] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ExtempStorageRule], Error>) in
            queue.async {
                do {
                    let rows = try self.sqlite.queryRows(
                        sql: """
                        SELECT *
                        FROM v_substance_storage_rules
                        WHERE substance_id = ?;
                        """,
                        binds: [.int(Int64(substanceId))]
                    )

                    let out: [ExtempStorageRule] = rows.compactMap { r in
                        let substanceId = Int((r["substance_id"] ?? nil) ?? "")
                        let propertyTitleUk = ((r["property_title_uk"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let extraConditionsUk = ((r["extra_conditions_uk"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameLatNom = ((r["name_lat_nom"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameLatGen = ((r["name_lat_gen"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let listCode = ((r["list_code"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let noteUk = ((r["note_uk"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                        guard let substanceId, !propertyTitleUk.isEmpty else { return nil }
                        return ExtempStorageRule(
                            substanceId: substanceId,
                            propertyTitleUk: propertyTitleUk,
                            extraConditionsUk: extraConditionsUk,
                            nameLatNom: nameLatNom,
                            nameLatGen: nameLatGen,
                            listCode: listCode,
                            noteUk: noteUk
                        )
                    }

                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func distinctStoragePropertyTitles(substanceIds: [Int]) async throws -> [String] {
        let ids = substanceIds
            .map { Int64($0) }
            .filter { $0 > 0 }

        if ids.isEmpty { return [] }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            queue.async {
                do {
                    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                    let sql = """
                    SELECT DISTINCT property_title_uk
                    FROM v_substance_storage_rules
                    WHERE substance_id IN (\(placeholders));
                    """
                    let binds: [SQLiteValue] = ids.map { .int(Int64($0)) }
                    let rows = try self.sqlite.queryRows(sql: sql, binds: binds)

                    let titles = rows
                        .compactMap { (($0["property_title_uk"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    continuation.resume(returning: titles)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
