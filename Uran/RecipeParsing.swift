import Foundation

enum RecipeParsing {
    struct ParsedDosageFormText: Hashable {
        var normalizedText: String
        var rawStrengthText: String
        var strengthText: String
        var isComplexStrength: Bool

        var formNorm: String
        var form: RecipeForm
        var formContext: String
        var routeOfAdministration: String

        var packCount: Int?
        var packUnit: String
        var packVolumeMl: Double?
        var container: String

        var dosageSuggestion: String
        var quantityNSuggestion: String
        var volumeSuggestion: String
    }

    static func extractConcentration(from text: String) -> String {
        let preprocessed = text
        let fullRange = NSRange(preprocessed.startIndex..<preprocessed.endIndex, in: preprocessed)

        let num = "(\\d+(?:[\\.,]\\d+)?)"
        let unit = "(мкг|mcg|µg|ug|мг|mg|г|g|МЕ|ME|IU|ЕД|%)"
        let vol = "(мл|ml|л|l)"

        let patterns = [
            "\\b\(num)\\s*\(unit)\\s*/\\s*\(num)\\s*\(vol)\\b",
            "\\b\(num)\\s*\(unit)\\s*/\\s*\(vol)\\b"
        ]

        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: preprocessed, options: [], range: fullRange),
               let rr = Range(m.range, in: preprocessed) {
                let raw = String(preprocessed[rr])
                return raw
                    .replacingOccurrences(of: "МЕ", with: "ME")
                    .replacingOccurrences(of: "ме", with: "ME")
                    .replacingOccurrences(of: "мл", with: "ml")
            }
        }

        return ""
    }

    struct ParsedDosageFormTextDTO: Codable {
        var normalizedText: String
        var rawStrengthText: String
        var strengthText: String
        var isComplexStrength: Bool

        var formNorm: String
        var formRawValue: String
        var formContext: String
        var routeOfAdministration: String

        var packCount: Int?
        var packUnit: String
        var packVolumeMl: Double?
        var container: String
    }

    struct ParsedDosageFormTextBundleDTO: Codable {
        var version: Int
        var selectedIndex: Int
        var variants: [ParsedDosageFormTextDTO]
    }

    static func encodeParsedDosage(_ parsed: ParsedDosageFormText) -> String {
        let dto = ParsedDosageFormTextDTO(
            normalizedText: parsed.normalizedText,
            rawStrengthText: parsed.rawStrengthText,
            strengthText: parsed.strengthText,
            isComplexStrength: parsed.isComplexStrength,
            formNorm: parsed.formNorm,
            formRawValue: parsed.form.rawValue,
            formContext: parsed.formContext,
            routeOfAdministration: parsed.routeOfAdministration,
            packCount: parsed.packCount,
            packUnit: parsed.packUnit,
            packVolumeMl: parsed.packVolumeMl,
            container: parsed.container
        )
        guard let data = try? JSONEncoder().encode(dto) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func encodeParsedDosageBundle(variants: [ParsedDosageFormText], selectedIndex: Int) -> String {
        let dtos: [ParsedDosageFormTextDTO] = variants.map { v in
            ParsedDosageFormTextDTO(
                normalizedText: v.normalizedText,
                rawStrengthText: v.rawStrengthText,
                strengthText: v.strengthText,
                isComplexStrength: v.isComplexStrength,
                formNorm: v.formNorm,
                formRawValue: v.form.rawValue,
                formContext: v.formContext,
                routeOfAdministration: v.routeOfAdministration,
                packCount: v.packCount,
                packUnit: v.packUnit,
                packVolumeMl: v.packVolumeMl,
                container: v.container
            )
        }

        let dto = ParsedDosageFormTextBundleDTO(
            version: 1,
            selectedIndex: max(0, min(selectedIndex, max(dtos.count - 1, 0))),
            variants: dtos
        )

        guard let data = try? JSONEncoder().encode(dto) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decodeParsedDosageBundle(_ json: String) -> (variants: [ParsedDosageFormText], selectedIndex: Int)? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        if let bundle = try? JSONDecoder().decode(ParsedDosageFormTextBundleDTO.self, from: data) {
            let variants: [ParsedDosageFormText] = bundle.variants.compactMap { dto in
                decodeParsedDosageDTO(dto)
            }
            guard !variants.isEmpty else { return nil }
            let idx = max(0, min(bundle.selectedIndex, variants.count - 1))
            return (variants, idx)
        }

        if let dto = try? JSONDecoder().decode(ParsedDosageFormTextDTO.self, from: data),
           let parsed = decodeParsedDosageDTO(dto) {
            return ([parsed], 0)
        }

        return nil
    }

    private static func decodeParsedDosageDTO(_ dto: ParsedDosageFormTextDTO) -> ParsedDosageFormText? {
        let form = RecipeForm(rawValue: dto.formRawValue) ?? .tab

        let volumeSuggestion: String
        if let ml = dto.packVolumeMl {
            volumeSuggestion = "\(formatNumberForDisplay(ml)) ml"
        } else {
            volumeSuggestion = ""
        }

        let quantityNSuggestion: String
        if let c = dto.packCount {
            quantityNSuggestion = "\(c)"
        } else {
            quantityNSuggestion = ""
        }

        let dosageSuggestion: String
        if dto.isComplexStrength {
            dosageSuggestion = ""
        } else {
            dosageSuggestion = dto.strengthText
        }

        return ParsedDosageFormText(
            normalizedText: dto.normalizedText,
            rawStrengthText: dto.rawStrengthText,
            strengthText: dto.strengthText,
            isComplexStrength: dto.isComplexStrength,
            formNorm: dto.formNorm,
            form: form,
            formContext: dto.formContext,
            routeOfAdministration: dto.routeOfAdministration,
            packCount: dto.packCount,
            packUnit: dto.packUnit,
            packVolumeMl: dto.packVolumeMl,
            container: dto.container,
            dosageSuggestion: dosageSuggestion,
            quantityNSuggestion: quantityNSuggestion,
            volumeSuggestion: volumeSuggestion
        )
    }

    static func decodeParsedDosage(_ json: String) -> ParsedDosageFormText? {
        guard let bundle = decodeParsedDosageBundle(json) else { return nil }
        return bundle.variants[bundle.selectedIndex]
    }

    static func parseDosageFormTextVariants(raw: String, composition: String) -> (variants: [ParsedDosageFormText], selectedIndex: Int) {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRaw.isEmpty {
            let single = parseDosageFormText(raw: raw, composition: composition)
            return ([single], 0)
        }

        let parts = trimmedRaw
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count <= 1 {
            let single = parseDosageFormText(raw: raw, composition: composition)
            return ([single], 0)
        }

        let variants = parts.map { p in
            parseDosageFormText(raw: p, composition: composition)
        }

        func score(_ v: ParsedDosageFormText) -> Int {
            var s = 0
            if v.form != .tab { s += 50 }
            if !v.strengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !v.isComplexStrength { s += 20 }
            if v.packCount != nil { s += 10 }
            if v.packVolumeMl != nil { s += 6 }
            if !v.container.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s += 4 }
            if v.isComplexStrength { s -= 30 }
            if v.formNorm == "tablets" { s -= 5 }
            return s
        }

        var bestIndex = 0
        var bestScore = score(variants[0])
        if variants.count >= 2 {
            for i in 1..<variants.count {
                let sc = score(variants[i])
                if sc > bestScore {
                    bestScore = sc
                    bestIndex = i
                }
            }
        }

        return (variants, bestIndex)
    }

    static func parseDosageFormText(raw: String, composition: String) -> ParsedDosageFormText {
        let combined = (raw + " " + composition).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = preprocessDosageText(combined)

        let formInfo = detectForm(in: normalized)
        let strengthInfo = detectStrength(in: normalized, form: formInfo.form)
        let packInfo = detectPack(in: normalized, form: formInfo.form)

        let dosageSuggestion: String
        if strengthInfo.isComplex {
            dosageSuggestion = ""
        } else {
            dosageSuggestion = strengthInfo.primaryText
        }

        let quantityNSuggestion: String
        if let c = packInfo.count {
            quantityNSuggestion = "\(c)"
        } else {
            quantityNSuggestion = ""
        }

        let volumeSuggestion: String
        if let ml = packInfo.volumeMl {
            volumeSuggestion = "\(formatNumberForDisplay(ml)) ml"
        } else {
            volumeSuggestion = ""
        }

        return ParsedDosageFormText(
            normalizedText: normalized,
            rawStrengthText: strengthInfo.rawText,
            strengthText: strengthInfo.primaryText,
            isComplexStrength: strengthInfo.isComplex,
            formNorm: formInfo.formNorm,
            form: formInfo.form,
            formContext: formInfo.context,
            routeOfAdministration: formInfo.route,
            packCount: packInfo.count,
            packUnit: packInfo.unit,
            packVolumeMl: packInfo.volumeMl,
            container: packInfo.container,
            dosageSuggestion: dosageSuggestion,
            quantityNSuggestion: quantityNSuggestion,
            volumeSuggestion: volumeSuggestion
        )
    }

    static func inferForm(from text: String) -> RecipeForm {
        let lower = text.lowercased()

        if lower.contains("наруж") || lower.contains("extern") || lower.contains("ad usum extern") {
            if lower.contains("р-р") || lower.contains("розчин") || lower.contains("раств") || lower.contains("sol") || lower.contains("solution") {
                return .solExt
            }
        }

        // Drops
        if lower.contains("капли") || lower.contains("gutt") || lower.contains("drops") {
            return .gutt
        }

        if lower.contains("сусп") || lower.contains("susp") || lower.contains("suspension") {
            return .susp
        }

        if lower.contains("эмуль") || lower.contains("emuls") || lower.contains("emulsion") {
            return .emuls
        }

        // Suppositories
        if lower.contains("свеч") || lower.contains("супозит") || lower.contains("супп") || lower.contains("supp") || lower.contains("suppository") || lower.contains("suppos") {
            return .supp
        }

        // Lyophilizate / powder
        if lower.contains("лиофил") || lower.contains("лиоф") || lower.contains("lyoph") || lower.contains("lyophiliz") {
            return .lyoph
        }
        if lower.contains("пор") || lower.contains("порош") || lower.contains("pulv") || lower.contains("powder") {
            return .pulv
        }

        // Spray
        if lower.contains("спрей") || lower.contains("spray") || lower.contains("spr") {
            return .spr
        }

        // Concentrate
        if lower.contains("концентрат") || lower.contains("concentrate") || lower.contains("conc") {
            return .conc
        }

        // Tincture
        if lower.contains("наст") || lower.contains("настой") || lower.contains("tinct") || lower.contains("tinct.") || lower.contains("прим. фл") {
            return .tinct
        }

        // Tablets
        if lower.contains("табл") || lower.contains("tablet") {
            return .tab
        }

        // Capsules
        if lower.contains("капсул") || lower.contains("caps") {
            return .caps
        }

        // Ampoules
        if lower.contains("амп") || lower.contains("amp") {
            return .amp
        }

        if lower.contains("гель") || lower.contains("gel") {
            return .gel
        }

        if lower.contains("паста") || lower.contains("past") {
            return .past
        }

        if lower.contains("линим") || lower.contains("linim") {
            return .linim
        }

        // Ointment / cream
        if lower.contains("крем") || lower.contains("crem") || lower.contains("cream") {
            return .crem
        }
        if lower.contains("маз") || lower.contains("ung") {
            return .ung
        }

        // Solutions
        if lower.contains("р-р") || lower.contains("розчин") || lower.contains("раств") || lower.contains("sol") || lower.contains("фл") || lower.contains("solution") {
            return .sol
        }

        if lower.contains("сироп") || lower.contains("syrup") || lower.contains("sir.") || lower.contains(" sir ") {
            return .sir
        }
        return .tab
    }

    static func extractDose(from text: String) -> String {
        let preprocessed = text
        let fullRange = NSRange(preprocessed.startIndex..<preprocessed.endIndex, in: preprocessed)

        let percentPattern = "(\\d+(?:[\\.,]\\d+)?)\\s*%"
        if let re = try? NSRegularExpression(pattern: percentPattern, options: [.caseInsensitive]),
           let m = re.firstMatch(in: preprocessed, options: [], range: fullRange),
           let r1 = Range(m.range(at: 1), in: preprocessed) {
            let num = String(preprocessed[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(num)%"
        }

        let unitPattern = "(\\d+(?:[\\.,]\\d+)?)\\s*(мкг|mcg|µg|ug|мг|mg|г|g|мл|ml|л|l|МЕ|ME|IU|ЕД)"
        guard let re = try? NSRegularExpression(pattern: unitPattern, options: [.caseInsensitive]) else { return "" }
        guard let m = re.firstMatch(in: preprocessed, options: [], range: fullRange) else { return "" }
        if let r1 = Range(m.range(at: 1), in: preprocessed), let r2 = Range(m.range(at: 2), in: preprocessed) {
            let num = String(preprocessed[r1]).replacingOccurrences(of: ",", with: ".")
            let unitRaw = String(preprocessed[r2])
            let unit = normalizeDoseUnit(unitRaw)
            return "\(num) \(unit)"
        }
        return ""
    }

    private static func normalizeDoseUnit(_ unit: String) -> String {
        let lower = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "мкг": return "mcg"
        case "µg": return "mcg"
        case "ug": return "mcg"
        case "mcg": return "mcg"
        case "мг": return "mg"
        case "mg": return "mg"
        case "г": return "g"
        case "g": return "g"
        case "мл": return "ml"
        case "ml": return "ml"
        case "л": return "l"
        case "l": return "l"
        case "ме": return "ME"
        case "iu": return "ME"
        case "me": return "ME"
        case "ед": return "ED"
        default:
            return unit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func extractQuantityN(from text: String) -> String {
        let preprocessed = text
        let patternNo = "№\\s*(\\d{1,4})(?!\\s*[\\/-])"
        if let re = try? NSRegularExpression(pattern: patternNo, options: []) {
            let range = NSRange(preprocessed.startIndex..<preprocessed.endIndex, in: preprocessed)
            if let m = re.firstMatch(in: preprocessed, options: [], range: range),
               let r = Range(m.range(at: 1), in: preprocessed) {
                return String(preprocessed[r])
            }
        }

        let patternPo = "по\\s+(\\d{1,4})\\s+(таблет|табл|капсул|капс|ампул|амп)"
        if let re = try? NSRegularExpression(pattern: patternPo, options: [.caseInsensitive]) {
            let range = NSRange(preprocessed.startIndex..<preprocessed.endIndex, in: preprocessed)
            if let m = re.firstMatch(in: preprocessed, options: [], range: range),
               let r = Range(m.range(at: 1), in: preprocessed) {
                return String(preprocessed[r])
            }
        }

        if inferForm(from: preprocessed) == .ung {
            let lower = preprocessed.lowercased()
            if lower.contains("маз") || lower.contains("ung") {
                let massPattern = "(\\d+(?:[\\.,]\\d+)?)\\s*(?:г|g)\\b"
                if let re = try? NSRegularExpression(pattern: massPattern, options: [.caseInsensitive]) {
                    let range = NSRange(preprocessed.startIndex..<preprocessed.endIndex, in: preprocessed)
                    let matches = re.matches(in: preprocessed, options: [], range: range)
                    if let last = matches.last, let r1 = Range(last.range(at: 1), in: preprocessed) {
                        let raw = String(preprocessed[r1]).replacingOccurrences(of: ",", with: ".")
                        if let val = Double(raw) {
                            let formatted = String(format: "%.1f", val).replacingOccurrences(of: ".", with: ",")
                            return formatted
                        }
                    }
                }
            }
        }

        return ""
    }

    static func signaSuggestion(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.count <= 200 { return trimmed }

        let prefix = String(trimmed.prefix(240))
        if let dot = prefix.firstIndex(of: ".") {
            let sentence = String(prefix[...dot]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { return sentence }
        }

        return String(trimmed.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct FormDetectionResult {
        var formNorm: String
        var form: RecipeForm
        var context: String
        var route: String
    }

    private struct StrengthDetectionResult {
        var rawText: String
        var primaryText: String
        var isComplex: Bool
    }

    private struct PackDetectionResult {
        var count: Int?
        var unit: String
        var volumeMl: Double?
        var container: String
    }

    private static func preprocessDosageText(_ text: String) -> String {
        var s = text.lowercased()

        let separators: [String] = [";", ":", "(", ")", "[", "]", "{", "}", "–", "—", "-", "•", "·", "|", "\\n", "\\t"]
        for sep in separators {
            s = s.replacingOccurrences(of: sep, with: " ")
        }

        let replacements: [(String, String)] = [
            ("мг/мл", "mg/ml"),
            ("г/мл", "g/ml"),
            ("мкг/доза", "mcg/dose"),
            ("мкг/доз", "mcg/dose"),
            ("мг/доза", "mg/dose"),
            ("мг/доз", "mg/dose"),
            ("mg/ml", "mg/ml"),
            ("мг", "mg"),
            ("мкг", "mcg"),
            ("µg", "mcg"),
            ("ug", "mcg"),
            ("мл", "ml"),
            ("ме", "iu"),
            ("iu", "iu"),
            ("№", " no "),
            ("n°", " no "),
            ("no", " no "),
            ("шт", " pcs "),
            ("таб", " tab "),
            ("табл", " tab "),
            ("таблет", " tablet "),
            ("капс", " caps "),
            ("капсул", " capsule "),
            ("амп", " amp "),
            ("фл", " vial ")
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // Convert Cyrillic single-letter units ONLY when they appear as standalone tokens.
        // (Avoid breaking words like "аерозоль", "ингаляция" etc.)
        s = s.replacingOccurrences(of: " г ", with: " g ")
        s = s.replacingOccurrences(of: " л ", with: " l ")

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectForm(in normalized: String) -> FormDetectionResult {
        let t = normalized

        struct Candidate {
            let priority: Int
            let formNorm: String
            let form: RecipeForm
            let triggers: [String]
            let requiresAll: [String]
            let context: String
            let route: String

            init(
                priority: Int,
                formNorm: String,
                form: RecipeForm,
                triggers: [String],
                requiresAll: [String] = [],
                context: String,
                route: String
            ) {
                self.priority = priority
                self.formNorm = formNorm
                self.form = form
                self.triggers = triggers
                self.requiresAll = requiresAll
                self.context = context
                self.route = route
            }
        }

        let candidates: [Candidate] = [
            Candidate(priority: 113, formNorm: "inhalation_aerosol_mdi", form: .mdi, triggers: ["під тиском", "под давлен", "pressurized", "under pressure"], requiresAll: ["доз"], context: "inhal", route: "inhal"),
            Candidate(priority: 112, formNorm: "inhalation_aerosol_mdi", form: .mdi, triggers: ["aerosol", "аерозоль", "аэрозоль"], requiresAll: ["inhal", "доз"], context: "inhal", route: "inhal"),
            Candidate(priority: 112, formNorm: "inhalation_aerosol_mdi", form: .mdi, triggers: ["aerosol", "аерозоль", "аэрозоль"], requiresAll: ["інгал", "доз"], context: "inhal", route: "inhal"),
            Candidate(priority: 112, formNorm: "inhalation_aerosol_mdi", form: .mdi, triggers: ["aerosol", "аерозоль", "аэрозоль"], requiresAll: ["ингал", "доз"], context: "inhal", route: "inhal"),

            Candidate(priority: 111, formNorm: "inhalation_aerosol_mdi", form: .mdi, triggers: ["inhaler", "інгалятор", "ингалятор"], requiresAll: ["доз"], context: "inhal", route: "inhal"),
            Candidate(priority: 110, formNorm: "solution_external", form: .solExt, triggers: ["ad usum extern", "extern", "наруж"], context: "", route: "external"),

            Candidate(priority: 105, formNorm: "solution_injection", form: .amp, triggers: ["injection", "inject", "ін'ек", "инъек", "amp"], context: "", route: "parenteral"),
            Candidate(priority: 100, formNorm: "infusion_solution", form: .sol, triggers: ["infusion", "інфуз", "инфуз"], context: "", route: "parenteral"),
            Candidate(priority: 98, formNorm: "concentrate_infusion", form: .conc, triggers: ["concentrat", "concentrate", "conc", "концентрат"], context: "", route: "parenteral"),

            Candidate(priority: 90, formNorm: "eye_drops", form: .gutt, triggers: ["ophthalm", "офтал", "глаз"], context: "ophthalm", route: "local"),
            Candidate(priority: 88, formNorm: "ear_drops", form: .gutt, triggers: ["otic", "отик", "ух"], context: "otic", route: "local"),
            Candidate(priority: 86, formNorm: "nasal_drops", form: .gutt, triggers: ["nasal", "назал", "нос"], context: "nasal", route: "local"),
            Candidate(priority: 84, formNorm: "drops_generic", form: .gutt, triggers: ["gutt", "капл", "drops"], context: "", route: "local"),

            Candidate(priority: 82, formNorm: "nasal_spray", form: .spr, triggers: ["spray", "спрей"], requiresAll: ["nasal"], context: "nasal", route: "local"),
            Candidate(priority: 80, formNorm: "spray_generic", form: .spr, triggers: ["spray", "спрей", "aerosol"], context: "", route: "local"),

            Candidate(priority: 78, formNorm: "suppositories", form: .supp, triggers: ["supp", "супп", "свеч"], context: "", route: "local"),

            Candidate(priority: 76, formNorm: "gel", form: .gel, triggers: ["gel", "гель"], context: "", route: "external"),
            Candidate(priority: 75, formNorm: "cream", form: .crem, triggers: ["crem", "cream", "крем"], context: "", route: "external"),
            Candidate(priority: 74, formNorm: "ointment", form: .ung, triggers: ["ung", "маз"], context: "", route: "external"),
            Candidate(priority: 73, formNorm: "paste", form: .past, triggers: ["past", "паста"], context: "", route: "external"),
            Candidate(priority: 72, formNorm: "liniment", form: .linim, triggers: ["linim", "линим"], context: "", route: "external"),

            Candidate(priority: 70, formNorm: "tablets", form: .tab, triggers: ["tablet", "tab"], context: "", route: "oral"),
            Candidate(priority: 69, formNorm: "capsules", form: .caps, triggers: ["capsule", "caps"], context: "", route: "oral"),

            Candidate(priority: 60, formNorm: "powder_injection", form: .lyoph, triggers: ["lyoph", "лиоф"], context: "", route: "parenteral"),
            Candidate(priority: 58, formNorm: "powder_oral", form: .pulv, triggers: ["pulv", "пор", "порош"], context: "", route: "oral"),

            Candidate(priority: 55, formNorm: "syrup", form: .sir, triggers: ["sir", "сироп"], context: "", route: "oral"),
            Candidate(priority: 54, formNorm: "suspension", form: .susp, triggers: ["susp", "сусп"], context: "", route: "oral"),
            Candidate(priority: 53, formNorm: "emulsion", form: .emuls, triggers: ["emuls", "эмуль"], context: "", route: "oral"),
            Candidate(priority: 52, formNorm: "solution", form: .sol, triggers: ["sol", "р-р", "розчин", "раств", "solution", "vial"], context: "", route: "oral"),
            Candidate(priority: 51, formNorm: "tincture", form: .tinct, triggers: ["tinct", "наст"], context: "", route: "oral")
        ]

        func containsAny(_ arr: [String]) -> Bool {
            for a in arr {
                if t.contains(a) { return true }
            }
            return false
        }

        func containsAll(_ arr: [String]) -> Bool {
            for a in arr {
                if !t.contains(a) { return false }
            }
            return true
        }

        var best: Candidate?
        for c in candidates {
            if !containsAny(c.triggers) { continue }
            if !containsAll(c.requiresAll) { continue }
            if best == nil || c.priority > (best?.priority ?? -1) {
                best = c
            }
        }

        if let best {
            return FormDetectionResult(formNorm: best.formNorm, form: best.form, context: best.context, route: best.route)
        }

        return FormDetectionResult(formNorm: "tablets", form: .tab, context: "", route: "")
    }

    private static func detectStrength(in normalized: String, form: RecipeForm) -> StrengthDetectionResult {
        let t = normalized

        if t.contains("~") {
            return StrengthDetectionResult(rawText: "~", primaryText: "", isComplex: false)
        }

        let fullRange = NSRange(t.startIndex..<t.endIndex, in: t)
        let datePattern = "\\b\\d{1,2}[\\./]\\d{1,2}[\\./]\\d{2,4}\\b"
        if let reDate = try? NSRegularExpression(pattern: datePattern, options: []),
           reDate.firstMatch(in: t, options: [], range: fullRange) != nil {
            return StrengthDetectionResult(rawText: "", primaryText: "", isComplex: true)
        }

        let unitGroup = "(?:mcg|mg|g|iu|mmol|%)"
        let num = "(\\d+(?:[\\.,]\\d+)?)"

        if form == .mdi {
            let doseWord = "(?:dose|доз(?:а|у|ы|)|doses)"
            // NOTE: Avoid using \b (word boundary) here: it is based on ASCII \w in ICU and may fail with Cyrillic,
            // e.g. it may not match reliably around "дозу".
            let perDosePattern = "(?:^|\\s)\(num)\\s*\(unitGroup)\\s*/\\s*\(doseWord)(?=\\s|$)"
            let nearDosePattern = "(?:^|\\s)\(num)\\s*\(unitGroup)(?=\\s|$)(?:\\s+\(doseWord)|\\s+(?:na|на)\\s*\\d+\\s*\(doseWord))"

            func normalizePerDose(_ raw: String) -> String {
                var s = raw
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "мкг", with: "mcg")
                    .replacingOccurrences(of: "µg", with: "mcg")
                    .replacingOccurrences(of: "ug", with: "mcg")
                s = s.replacingOccurrences(of: "дозу", with: "dose")
                s = s.replacingOccurrences(of: "доза", with: "dose")
                s = s.replacingOccurrences(of: "дозы", with: "dose")
                s = s.replacingOccurrences(of: "доз", with: "dose")

                // Convert mg/dose to mcg/dose when possible.
                let mgPattern = "^(\\d+(?:\\.\\d+)?)\\s*mg\\s*/\\s*dose$"
                if let re = try? NSRegularExpression(pattern: mgPattern, options: [.caseInsensitive]) {
                    let range = NSRange(s.startIndex..<s.endIndex, in: s)
                    if let m = re.firstMatch(in: s, options: [], range: range),
                       let r1 = Range(m.range(at: 1), in: s),
                       let val = Double(String(s[r1])) {
                        let mcg = val * 1000.0
                        let mcgStr: String
                        if mcg.rounded(.towardZero) == mcg {
                            mcgStr = String(Int(mcg))
                        } else {
                            mcgStr = String(mcg)
                        }
                        return "\(mcgStr) mcg/dose".replacingOccurrences(of: ".", with: ",")
                    }
                }
                return s.replacingOccurrences(of: ".", with: ",")
            }

            if let re = try? NSRegularExpression(pattern: perDosePattern, options: [.caseInsensitive]),
               let m = re.firstMatch(in: t, options: [], range: fullRange),
               let r = Range(m.range, in: t) {
                let raw = String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "мл", with: "ml")
                let cleaned = raw
                    .replacingOccurrences(of: "mcg", with: "mcg")
                    .replacingOccurrences(of: "mg", with: "mg")
                let normalized = normalizePerDose(cleaned)
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "/", with: "/")
                return StrengthDetectionResult(rawText: raw, primaryText: normalized, isComplex: false)
            }

            if let re = try? NSRegularExpression(pattern: nearDosePattern, options: [.caseInsensitive]),
               let m = re.firstMatch(in: t, options: [], range: fullRange),
               let r = Range(m.range, in: t) {
                // Take only the leading number+unit and normalize as "X mcg/dose".
                let raw = String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                let leadPattern = "^(\\d+(?:[\\.,]\\d+)?)\\s*(mcg|mg|g)"
                if let reLead = try? NSRegularExpression(pattern: leadPattern, options: [.caseInsensitive]) {
                    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
                    if let m2 = reLead.firstMatch(in: raw, options: [], range: range),
                       let r1 = Range(m2.range(at: 1), in: raw),
                       let r2 = Range(m2.range(at: 2), in: raw) {
                        let v = String(raw[r1]).replacingOccurrences(of: ",", with: ".")
                        let u = String(raw[r2]).lowercased()
                        if u == "mg", let val = Double(v) {
                            let mcg = val * 1000.0
                            let mcgStr: String
                            if mcg.rounded(.towardZero) == mcg {
                                mcgStr = String(Int(mcg))
                            } else {
                                mcgStr = String(mcg)
                            }
                            return StrengthDetectionResult(rawText: raw, primaryText: "\(mcgStr)mcg/dose".replacingOccurrences(of: ".", with: ","), isComplex: false)
                        }
                        return StrengthDetectionResult(rawText: raw, primaryText: "\(v.replacingOccurrences(of: ".", with: ","))\(u)/dose", isComplex: false)
                    }
                }
            }

            return StrengthDetectionResult(rawText: "", primaryText: "", isComplex: false)
        }

        let concPattern = "\\b\(num)\\s*\(unitGroup)\\s*/\\s*\(num)?\\s*(?:ml|l)\\b"
        let concPattern2 = "\\b\(num)\\s*\(unitGroup)\\s*/\\s*(?:ml|l)\\b"
        let simplePattern = "\\b\(num)\\s*\(unitGroup)\\b"

        var foundStrengths: [String] = []

        if let re = try? NSRegularExpression(pattern: concPattern, options: [.caseInsensitive]) {
            let matches = re.matches(in: t, options: [], range: fullRange)
            for m in matches {
                if let r = Range(m.range, in: t) {
                    foundStrengths.append(String(t[r]))
                }
            }
        }
        if let re = try? NSRegularExpression(pattern: concPattern2, options: [.caseInsensitive]) {
            let matches = re.matches(in: t, options: [], range: fullRange)
            for m in matches {
                if let r = Range(m.range, in: t) {
                    foundStrengths.append(String(t[r]))
                }
            }
        }

        if foundStrengths.isEmpty, let re = try? NSRegularExpression(pattern: simplePattern, options: [.caseInsensitive]) {
            let matches = re.matches(in: t, options: [], range: fullRange)
            for m in matches {
                if let r = Range(m.range, in: t) {
                    foundStrengths.append(String(t[r]))
                }
            }
        }

        if foundStrengths.count >= 5 {
            return StrengthDetectionResult(rawText: foundStrengths.joined(separator: "; "), primaryText: "", isComplex: true)
        }

        let hasMultiComponent = t.contains("+") || t.contains("комбин")
        if hasMultiComponent, foundStrengths.count >= 2 {
            return StrengthDetectionResult(rawText: foundStrengths.joined(separator: "; "), primaryText: "", isComplex: true)
        }

        func normalizeStrengthToken(_ token: String) -> String {
            var s = token.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "  ", with: " ")
            s = s.replacingOccurrences(of: "mcg", with: "mcg")
            s = s.replacingOccurrences(of: "iu", with: "ME")
            s = s.replacingOccurrences(of: ",", with: ".")
            return s
        }

        let rawText = foundStrengths.joined(separator: "; ")
        if rawText.contains("/") {
            let primary = normalizeStrengthToken(foundStrengths.first ?? "")
            let display = primary.replacingOccurrences(of: ".", with: ",")
            return StrengthDetectionResult(rawText: rawText, primaryText: display, isComplex: false)
        }

        if let first = foundStrengths.first {
            let primary = normalizeStrengthToken(first)
            let display = primary.replacingOccurrences(of: ".", with: ",")
            return StrengthDetectionResult(rawText: rawText, primaryText: display, isComplex: false)
        }

        return StrengthDetectionResult(rawText: "", primaryText: "", isComplex: false)
    }

    private static func detectPack(in normalized: String, form: RecipeForm) -> PackDetectionResult {
        let t = normalized
        let fullRange = NSRange(t.startIndex..<t.endIndex, in: t)

        var count: Int?
        var unit: String = ""
        var container: String = ""

        if form == .mdi {
            // doses_count: "200 доз" / "200 doses".
            let doseCountPattern = "\\b(\\d{2,4})\\s*(?:dos|dose|doses|доз)\\b"
            if let re = try? NSRegularExpression(pattern: doseCountPattern, options: [.caseInsensitive]),
               let m = re.firstMatch(in: t, options: [], range: fullRange),
               let r1 = Range(m.range(at: 1), in: t),
               let v = Int(String(t[r1])) {
                count = v
                unit = "dos"
            }

            if container.isEmpty {
                container = "canister"
            }

            if count == nil {
                // For MDI, default pack to 1 inhaler.
                count = 1
                unit = "canister"
            }
        }

        let patternNo = "\\bno\\s*(\\d{1,4})\\b"
        if let re = try? NSRegularExpression(pattern: patternNo, options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, options: [], range: fullRange),
           let r = Range(m.range(at: 1), in: t),
           let v = Int(String(t[r])) {
            count = v
        }

        if count == nil {
            let patternCountUnit = "\\b(\\d{1,4})\\s*(tab|tablet|caps|capsule|pcs)\\b"
            if let re = try? NSRegularExpression(pattern: patternCountUnit, options: [.caseInsensitive]),
               let m = re.firstMatch(in: t, options: [], range: fullRange),
               let r1 = Range(m.range(at: 1), in: t),
               let r2 = Range(m.range(at: 2), in: t),
               let v = Int(String(t[r1])) {
                count = v
                unit = String(t[r2])
            }
        }

        if unit.isEmpty {
            switch form {
            case .tab: unit = "tabs"
            case .caps: unit = "caps"
            case .amp: unit = "amps"
            default: unit = ""
            }
        }

        let mlPattern = "\\b(\\d+(?:[\\.,]\\d+)?)\\s*(?:ml)\\b"
        var volumeMl: Double?
        if let re = try? NSRegularExpression(pattern: mlPattern, options: [.caseInsensitive]) {
            let matches = re.matches(in: t, options: [], range: fullRange)
            if let last = matches.last, let r1 = Range(last.range(at: 1), in: t) {
                let num = String(t[r1]).replacingOccurrences(of: ",", with: ".")
                volumeMl = Double(num)
            }
        }

        if t.contains("amp") || t.contains("амп") {
            container = "amp"
        } else if t.contains("vial") || t.contains("флакон") {
            container = "vial"
        } else if t.contains("syringe") || t.contains("шприц") {
            container = "syringe"
        } else if t.contains("bag") || t.contains("пакет") {
            container = "bag"
        }

        return PackDetectionResult(count: count, unit: unit, volumeMl: volumeMl, container: container)
    }

    private static func formatNumberForDisplay(_ v: Double) -> String {
        let s = String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
        return s.replacingOccurrences(of: ",00", with: "")
    }
}
