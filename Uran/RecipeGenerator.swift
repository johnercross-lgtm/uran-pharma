import Foundation

enum RecipeForm: String, CaseIterable, Identifiable {
    case tab = "tab."
    case caps = "caps."
    case mdi = "mdi."
    case sol = "sol."
    case solExt = "sol.ext."
    case gutt = "gutt."
    case sir = "sir."
    case susp = "susp."
    case emuls = "emuls."
    case tinct = "tinct."
    case ung = "ung."
    case crem = "crem."
    case gel = "gel."
    case past = "past."
    case linim = "linim."
    case amp = "amp."
    case conc = "conc."
    case spr = "spr."
    case pulv = "pulv."
    case lyoph = "lyoph."
    case supp = "supp."

    var id: String { rawValue }
}

struct RecipeDraft: Hashable {
    var innName: String
    var brandName: String
    var form: RecipeForm
    var dosage: String
    var quantityN: String
    var volume: String
    var signa: String
    var useTradeName: Bool
}

enum RecipeOutputFormat: String, CaseIterable, Identifiable {
    case short
    case expanded
    case brand
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: return "Короткий"
        case .expanded: return "Развёрнутый"
        case .brand: return "По бренду"
        case .json: return "JSON"
        }
    }
}

enum RecipeGenerator {
    private static func parseMlValue(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let pattern = "(\\d+(?:[\\.,]\\d+)?)\\s*(?:ml|мл)\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let m = re.firstMatch(in: trimmed, options: [], range: range) else { return nil }
        guard let r1 = Range(m.range(at: 1), in: trimmed) else { return nil }
        let num = String(trimmed[r1]).replacingOccurrences(of: ",", with: ".")
        return Double(num)
    }

    private static func sanitizeTradeName(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "®", with: "")
        s = s.replacingOccurrences(of: "™", with: "")
        s = s.replacingOccurrences(of: "℠", with: "")
        s = s.replacingOccurrences(of: "(R)", with: "")
        s = s.replacingOccurrences(of: "(r)", with: "")
        s = s.replacingOccurrences(of: "(TM)", with: "")
        s = s.replacingOccurrences(of: "(tm)", with: "")
        s = s.replacingOccurrences(of: "(SM)", with: "")
        s = s.replacingOccurrences(of: "(sm)", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        let locale = Locale(identifier: "ru_UA")
        let title = s.lowercased(with: locale).capitalized(with: locale)
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quoteTradeName(_ name: String) -> String {
        let trimmed = sanitizeTradeName(name)
        if trimmed.isEmpty { return trimmed }
        if trimmed.contains("\"") { return trimmed }
        if trimmed.contains("«") || trimmed.contains("»") { return trimmed }
        return "\"\(trimmed)\""
    }

    private static func brandFormAccusative(_ form: RecipeForm) -> String {
        switch form {
        case .tab: return "Tabulettas"
        case .caps: return "Capsulas"
        case .supp: return "Suppositoria"
        case .pulv: return "Pulveres"
        case .lyoph: return "Pulveres"
        case .mdi: return "Aerosolum"
        case .sol: return "Solutionem"
        case .solExt: return "Solutionem"
        case .gutt: return "Guttas"
        case .sir: return "Sirupum"
        case .susp: return "Suspensionem"
        case .emuls: return "Emulsionem"
        case .tinct: return "Tincturam"
        case .amp: return "Solutionem"
        case .spr: return "Spray"
        case .ung: return "Unguentum"
        case .crem: return "Cremam"
        case .gel: return "Gel"
        case .past: return "Pastam"
        case .linim: return "Linimentum"
        case .conc: return "Concentratum"
        }
    }

    private static func formKey(_ form: RecipeForm) -> String {
        switch form {
        case .tab: return "tab"
        case .caps: return "caps"
        case .mdi: return "mdi"
        case .sol: return "sol"
        case .solExt: return "solExt"
        case .gutt: return "gutt"
        case .sir: return "sir"
        case .susp: return "susp"
        case .emuls: return "emuls"
        case .tinct: return "tinct"
        case .ung: return "ung"
        case .crem: return "crem"
        case .gel: return "gel"
        case .past: return "past"
        case .linim: return "linim"
        case .amp: return "amp"
        case .conc: return "conc"
        case .spr: return "spr"
        case .pulv: return "pulv"
        case .lyoph: return "lyoph"
        case .supp: return "supp"
        }
    }

    static func generateBrandText(draft: RecipeDraft, settings: RecipeSettings) -> String {
        let trade = draft.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let doseRaw = draft.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = normalizeDose(doseRaw).replacingOccurrences(of: ".", with: ",")
        let qtyRaw = draft.quantityN.trimmingCharacters(in: .whitespacesAndNewlines)
        let volumeRaw = draft.volume.trimmingCharacters(in: .whitespacesAndNewlines)

        let formAcc = brandFormAccusative(draft.form)

        var rpParts: [String] = []
        rpParts.append(settings.standardPhrases.recipeStart)
        rpParts.append(formAcc)
        if draft.form == .sir || draft.form == .tinct || draft.form == .gutt {
            if !trade.isEmpty {
                rpParts.append(quoteTradeName(trade))
            }
        } else if !trade.isEmpty {
            rpParts.append(trade)
        }
        if !dose.isEmpty {
            rpParts.append(dose)
        }

        if (draft.form == .tab || draft.form == .caps || draft.form == .supp || draft.form == .pulv),
           !qtyRaw.isEmpty,
           let nInt = Int(qtyRaw) {
            rpParts.append("№\(nInt)")
        } else if (draft.form == .sol || draft.form == .gutt || draft.form == .sir || draft.form == .tinct || draft.form == .ung), !qtyRaw.isEmpty {
            rpParts.append(qtyRaw)
        } else if (draft.form == .sir || draft.form == .tinct), !volumeRaw.isEmpty {
            rpParts.append(volumeRaw)
        } else if draft.form == .gutt, !volumeRaw.isEmpty {
            rpParts.append(volumeRaw)
        }

        var lines: [String] = []
        lines.append(rpParts.joined(separator: " ").trimmingCharacters(in: .whitespaces))

        if draft.form == .amp, let nInt = Int(qtyRaw) {
            lines.append("D. t. d. №\(nInt) in amp.")
        }

        let signa = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)
        if !signa.isEmpty {
            lines.append("D. S.: \(signa)")
        } else {
            lines.append("D. S.:")
        }

        return lines.joined(separator: "\n")
    }

    private static func shortFormPrefix(formShort: String) -> String {
        let lower = formShort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("tab") { return "Tab." }
        if lower.contains("caps") { return "Caps." }
        if lower.contains("supp") { return "Supp." }
        if lower.contains("amp") { return "Sol." }
        if lower.contains("spr") { return "Spr." }
        if lower.contains("mdi") { return "Aer. inhal. доз." }
        if lower.contains("conc") { return "Conc." }
        if lower.contains("sol") { return "Sol." }
        if lower.contains("gutt") { return "Gutt." }
        if lower.contains("sir") { return "Sir." }
        if lower.contains("susp") { return "Susp." }
        if lower.contains("emuls") { return "Emuls." }
        if lower.contains("tinct") { return "Tinct." }
        if lower.contains("ung") { return "Ung." }
        if lower.contains("crem") { return "Crem." }
        if lower.contains("gel") { return "Gel." }
        if lower.contains("past") { return "Past." }
        if lower.contains("linim") { return "Linim." }
        if lower.contains("pulv") { return "Pulv." }
        if lower.contains("lyoph") { return "Lyoph." }
        return "Rp.:"
    }

    private static func shortDtdLine(formShort: String, amount: Int) -> String {
        let lower = formShort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("amp") { return "D. t. d. N. \(amount) in amp." }
        if lower.contains("tab") { return "D. t. d. N. \(amount)" }
        if lower.contains("caps") { return "D. t. d. N. \(amount)" }
        if lower.contains("supp") { return "D. t. d. N. \(amount)" }
        if lower.contains("pulv") { return "D. t. d. N. \(amount)" }
        return "D. t. d. N. \(amount)"
    }

    private static func expandedFormPrefix(formFullLatin: String) -> String {
        let lower = formFullLatin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("tabulett") { return "Tabulettas" }
        if lower.contains("capsul") { return "Capsulas" }
        if lower.contains("solution") { return "Solutionis" }
        if lower.contains("ampull") { return "Solutionis" }
        if lower.contains("concentr") { return "Concentrati" }
        if lower.contains("suspens") { return "Suspensionis" }
        if lower.contains("emulsion") { return "Emulsionis" }
        if lower.contains("spray") { return "Spr." }
        if lower.contains("sirup") { return "Sir." }
        if lower.contains("tinctur") { return "Tinct." }
        if lower.contains("unguent") { return "Unguenti" }
        if lower.contains("crem") { return "Cremae" }
        if lower.contains("gel") { return "Gelii" }
        if lower.contains("past") { return "Pastae" }
        if lower.contains("liniment") { return "Linimenti" }
        if lower.contains("pulver") { return "Pulveris" }
        if lower.contains("lyoph") { return "Lyophilisati" }
        if lower.contains("suppos") { return "Suppositoriorum" }
        if lower.contains("gutt") { return "Gutt." }
        return ""
    }

    private static func expandedDtdLine(formFullLatin: String, amount: Int) -> String {
        let lower = formFullLatin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("ampull") {
            return "Da tales doses numero \(amount) in ampullis"
        }
        return "Da tales doses numero \(amount)"
    }

    static func declineInnToGenitive(_ inn: String, rules: [LatinSuffixRule]) -> String {
        LatinDeclension.toGenitive(inn, extraRules: rules)
    }

    static func normalizeDose(_ dosage: String) -> String {
        let trimmed = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        var s = trimmed
        s = s.replacingOccurrences(of: ",", with: ".")
        s = s.replacingOccurrences(of: "мкг", with: "mcg")
        s = s.replacingOccurrences(of: "мг", with: "mg")
        s = s.replacingOccurrences(of: "г", with: "g")
        s = s.replacingOccurrences(of: "мл", with: "ml")
        s = s.replacingOccurrences(of: "л", with: "l")
        s = s.replacingOccurrences(of: "МЕ", with: "ME")
        s = s.replacingOccurrences(of: "IU", with: "ME")

        // Academic rule for solid forms: show mg as grams without unit (500mg -> 0,5).
        // We only do it for a simple "<number> mg" case, not for fractions like mg/ml.
        let lower = s.lowercased()
        if lower.contains("mg"), !lower.contains("/"), !lower.contains("%") {
            let parsed = parseDose(s)
            if let v = parsed.value, (parsed.unit ?? "").lowercased() == "mg" {
                return formatNumericDoseValue(v, unit: "mg").replacingOccurrences(of: ".", with: ",")
            }
        }

        return s
    }

    static func generateText(draft: RecipeDraft, settings: RecipeSettings) -> String {
        let gen = declineInnToGenitive(draft.innName, rules: settings.grammarRules)
        let latinName = formatDrugName(gen)

        let dose = normalizeDose(draft.dosage)
        let n = draft.quantityN.trimmingCharacters(in: .whitespacesAndNewlines)
        let form = draft.form.rawValue
        let volume = draft.volume.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if draft.form == .sir {
            if !volume.isEmpty {
                if dose.isEmpty {
                    lines.append("\(settings.standardPhrases.recipeStart) Sir. \(latinName) \(volume)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("\(settings.standardPhrases.recipeStart) Sir. \(latinName) \(dose) — \(volume)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("\(settings.standardPhrases.recipeStart) Sir. \(latinName) \(dose)".trimmingCharacters(in: .whitespaces))
            }
        } else if draft.form == .tinct {
            if !volume.isEmpty {
                lines.append("\(settings.standardPhrases.recipeStart) Tinct. \(latinName) \(volume)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("\(settings.standardPhrases.recipeStart) Tinct. \(latinName)".trimmingCharacters(in: .whitespaces))
            }
        } else {
            lines.append("\(settings.standardPhrases.recipeStart) \(latinName) \(dose)".trimmingCharacters(in: .whitespaces))
        }
        if !n.isEmpty {
            lines.append("D.t.d. N. \(n) in \(form)")
        } else {
            lines.append("D.t.d. in \(form)")
        }
        lines.append(settings.standardPhrases.mixAndGive)
        if !draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("D. S.: \(draft.signa)")
        } else {
            lines.append("D. S.:")
        }

        return lines.joined(separator: "\n")
    }

    static func makePrescription(draft: RecipeDraft, settings: RecipeSettings, drugId: String?) -> Prescription {
        let nameGen: String = {
            if draft.useTradeName {
                let trade = draft.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
                if trade.isEmpty {
                    return declineInnToGenitive(draft.innName, rules: settings.grammarRules)
                }
                return quoteTradeName(trade)
            }
            return declineInnToGenitive(draft.innName, rules: settings.grammarRules)
        }()
        let parsed = parseDose(draft.dosage)
        let qtyTrimmed = draft.quantityN.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = qtyTrimmed.filter { $0.isNumber }
        let nInt = Int(qtyTrimmed) ?? (digits.isEmpty ? nil : Int(digits))
        let volumeTrimmed = draft.volume.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountRaw: String? = {
            if let _ = nInt {
                if volumeTrimmed.isEmpty { return nil }
                return volumeTrimmed
            }
            if !qtyTrimmed.isEmpty { return qtyTrimmed }
            if !volumeTrimmed.isEmpty { return volumeTrimmed }
            return nil
        }()

        let (formShort, formFull, instructionShort, instructionLatin) = makeSubscriptioParts(form: draft.form, amount: nInt)

        let material = PrescriptionMaterial(
            drugId: drugId,
            nameLatinGenetivus: nameGen,
            dosageValue: parsed.value,
            unit: parsed.unit,
            dosageRaw: parsed.value == nil ? draft.dosage.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        )

        let subscriptio = PrescriptionSubscriptio(
            formShort: formShort,
            formFullLatin: formFull,
            amount: nInt,
            amountRaw: amountRaw,
            instructionLatin: instructionLatin,
            instructionShort: instructionShort
        )

        return Prescription(
            header: PrescriptionHeader(id: nil, date: nil, patient: nil, doctor: nil),
            body: PrescriptionBody(
                invocation: settings.standardPhrases.recipeStart,
                designatioMateriarum: [material],
                subscriptio: subscriptio
            ),
            signatura: PrescriptionSignatura(
                language: "ru",
                text: draft.signa.trimmingCharacters(in: .whitespacesAndNewlines),
                durationDays: nil
            ),
            meta: PrescriptionMeta(isUrgent: false, isStale: false, storageLogic: nil)
        )
    }

    static func generateShortText(prescription: Prescription) -> String {
        guard let material = prescription.body.designatioMateriarum.first else { return "" }
        let name = capitalize(material.nameLatinGenetivus)
        var dose = formatDose(material)

        let amountRaw = (prescription.body.subscriptio.amountRaw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowerFullForm = prescription.body.subscriptio.formFullLatin.lowercased()
        let rpPrefix = lowerFullForm.contains("ampull") ? "Sol." : shortFormPrefix(formShort: prescription.body.subscriptio.formShort)
        let lowerForm = prescription.body.subscriptio.formShort.lowercased()

        if lowerForm.contains("mdi") {
            var lines: [String] = []
            let rpName = material.nameLatinGenetivus.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (rpName.contains("\"") || rpName.contains("«") || rpName.contains("»")) ? rpName : capitalize(rpName)
            let dosPart: String = {
                if let dos = prescription.body.subscriptio.amount, dos > 0 {
                    return ", №\(dos) dos."
                }
                return ""
            }()
            lines.append("Rp.: Aer. inhal. доз. \(displayName) \(dose)\(dosPart)".trimmingCharacters(in: .whitespaces))
            lines.append("D. t. d. №1")
            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("S.:")
            }
            return lines.joined(separator: "\n")
        }

        let largeVolumeSolution: Bool = {
            guard lowerForm.contains("sol") else { return false }
            if let ml = parseMlValue(amountRaw), ml >= 50 { return true }
            return false
        }()

        // If user entered a unitless small dose for a solution/ampoule and we know the volume in ml,
        // prefer showing concentration in percent (0,004 in 1 ml -> 0,4%).
        if (lowerFullForm.contains("ampull") || lowerForm.contains("sol") || lowerForm.contains("amp")),
           material.dosageValue != nil,
           (material.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = material.dosageValue,
           v > 0,
           v < 1,
           let ml = parseMlValue(amountRaw),
           ml > 0 {
            let percent = (v / ml) * 100.0
            dose = formatNumericDoseValue(percent, unit: "%") + "%"
        }

        if lowerForm.contains("tinct") {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                if dose.isEmpty {
                    lines.append("Rp.: \(rpPrefix) \(name) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }
            return lines.joined(separator: "\n")
        }

        if lowerForm.contains("conc") {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                if dose.isEmpty {
                    lines.append("Rp.: Conc. \(name) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("Rp.: Conc. \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("Rp.: Conc. \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            if let amount = prescription.body.subscriptio.amount {
                lines.append("D. t. d. N. \(amount) in flac.")
                let signa = prescription.signatura.text
                if !signa.isEmpty {
                    lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("S.:")
                }
            } else {
                let signa = prescription.signatura.text
                if !signa.isEmpty {
                    lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("D. S.:")
                }
            }

            return lines.joined(separator: "\n")
        }

        if lowerForm.contains("lyoph") {
            var lines: [String] = []
            lines.append("Rp.: Lyoph. \(name) \(dose)".trimmingCharacters(in: .whitespaces))

            if let amount = prescription.body.subscriptio.amount {
                lines.append("D. t. d. N. \(amount) in flac.")
                let signa = prescription.signatura.text
                if !signa.isEmpty {
                    lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("S.:")
                }
            } else {
                let signa = prescription.signatura.text
                if !signa.isEmpty {
                    lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("D. S.:")
                }
            }

            return lines.joined(separator: "\n")
        }

        let isLiquidBottleForm = lowerForm.contains("sir") || lowerForm.contains("susp") || lowerForm.contains("emuls")
        if isLiquidBottleForm {
            var lines: [String] = []
            let ml = parseMlValue(amountRaw)
            let hasSmallUnitVolume = (ml != nil && (ml ?? 0) > 0 && (ml ?? 0) <= 20)

            if !amountRaw.isEmpty {
                if dose.isEmpty {
                    lines.append("Rp.: \(rpPrefix) \(name) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            if hasSmallUnitVolume, let amount = prescription.body.subscriptio.amount {
                lines.append("D. t. d. N. \(amount)".trimmingCharacters(in: .whitespaces))
                let signa = prescription.signatura.text
                if !signa.isEmpty {
                    lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("S.:")
                }
                return lines.joined(separator: "\n")
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }
            return lines.joined(separator: "\n")
        }

        if largeVolumeSolution {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }

            return lines.joined(separator: "\n")
        }

        if (lowerFullForm.contains("ampull") || lowerForm.contains("amp")),
           let amount = prescription.body.subscriptio.amount {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }
            lines.append("D. t. d. N. \(amount) in amp.")

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("S.:")
            }

            return lines.joined(separator: "\n")
        }

        if lowerForm.contains("sir") {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                if dose.isEmpty {
                    lines.append("Rp.: \(rpPrefix) \(name) \(amountRaw)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }
            return lines.joined(separator: "\n")
        }

        if lowerForm.contains("spr") {
            var lines: [String] = []
            if !amountRaw.isEmpty {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }
            return lines.joined(separator: "\n")
        }
        if lowerForm.contains("ung") || lowerForm.contains("crem") || lowerForm.contains("gel") || lowerForm.contains("past") || lowerForm.contains("linim") {
            let amount = amountRaw
            var lines: [String] = []
            if !amount.isEmpty {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amount)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("D. S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("D. S.:")
            }

            return lines.joined(separator: "\n")
        }

        if (lowerForm.contains("tab") || lowerForm.contains("caps") || lowerForm.contains("supp")),
           let amount = prescription.body.subscriptio.amount {
            var lines: [String] = []
            lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            lines.append(shortDtdLine(formShort: prescription.body.subscriptio.formShort, amount: amount))

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("S.: \(signa)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("S.:")
            }

            return lines.joined(separator: "\n")
        }

        var lines: [String] = []
        var didAddDtd = false
        if !amountRaw.isEmpty {
            lines.append("Rp.: \(rpPrefix) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))
        } else {
            lines.append("Rp.: \(rpPrefix) \(name) \(dose)".trimmingCharacters(in: .whitespaces))

            if let amount = prescription.body.subscriptio.amount {
                let dtd = shortDtdLine(formShort: prescription.body.subscriptio.formShort, amount: amount)
                if !dtd.isEmpty {
                    lines.append(dtd)
                    didAddDtd = true
                }
            }
        }

        let signa = prescription.signatura.text
        if !signa.isEmpty {
            lines.append("\(didAddDtd ? "S.:" : "D. S.:") \(signa)".trimmingCharacters(in: .whitespaces))
        } else {
            lines.append(didAddDtd ? "S.:" : "D. S.:")
        }

        return lines.joined(separator: "\n")
    }

    static func generateExpandedText(prescription: Prescription) -> String {
        guard let material = prescription.body.designatioMateriarum.first else { return "" }
        let name = capitalize(material.nameLatinGenetivus)
        var dose = formatDose(material)

        let amountRaw = (prescription.body.subscriptio.amountRaw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []

        let expandedStart = "Recipe:"
        let fullForm = expandedFormPrefix(formFullLatin: prescription.body.subscriptio.formFullLatin)
        let lowerForm = prescription.body.subscriptio.formFullLatin.lowercased()

        let largeVolumeSolution: Bool = {
            guard lowerForm.contains("solution") else { return false }
            if let ml = parseMlValue(amountRaw), ml >= 50 { return true }
            return false
        }()

        // Same percent heuristic as in short text.
        if lowerForm.contains("solution") || lowerForm.contains("ampull"),
           material.dosageValue != nil,
           (material.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let v = material.dosageValue,
           v > 0,
           v < 1,
           let ml = parseMlValue(amountRaw),
           ml > 0 {
            let percent = (v / ml) * 100.0
            dose = formatNumericDoseValue(percent, unit: "%") + "%"
        }

        if prescription.body.subscriptio.formShort.lowercased().contains("tinct") {
            let amount = (prescription.body.subscriptio.amountRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !amount.isEmpty {
                lines.append("\(expandedStart) \(fullForm) \(name) \(amount)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("\(expandedStart) \(fullForm) \(name)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("Da. Signa: \(signa)")
            } else {
                lines.append("Da. Signa:")
            }
            return lines.joined(separator: "\n")
        }

        if prescription.body.subscriptio.formShort.lowercased().contains("sir") {
            let amount = (prescription.body.subscriptio.amountRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !amount.isEmpty {
                if dose.isEmpty {
                    lines.append("\(expandedStart) \(fullForm) \(name) \(amount)".trimmingCharacters(in: .whitespaces))
                } else {
                    lines.append("\(expandedStart) \(fullForm) \(name) \(dose) — \(amount)".trimmingCharacters(in: .whitespaces))
                }
            } else {
                lines.append("\(expandedStart) \(fullForm) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("Da. Signa: \(signa)")
            } else {
                lines.append("Da. Signa:")
            }
            return lines.joined(separator: "\n")
        }

        if prescription.body.subscriptio.formShort.lowercased().contains("spr") {
            let amount = (prescription.body.subscriptio.amountRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !amount.isEmpty {
                lines.append("\(expandedStart) \(fullForm) \(name) \(dose) — \(amount)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("\(expandedStart) \(fullForm) \(name) \(dose)".trimmingCharacters(in: .whitespaces))
            }

            let signa = prescription.signatura.text
            if !signa.isEmpty {
                lines.append("Da. Signa: \(signa)")
            } else {
                lines.append("Da. Signa:")
            }
            return lines.joined(separator: "\n")
        }
        var didAddDtd = false

        if lowerForm.contains("unguent") {
            let amount = prescription.body.subscriptio.amountRaw ?? ""
            lines.append("\(expandedStart) \(fullForm) \(name) \(dose) \(amount)".trimmingCharacters(in: .whitespaces))
        } else {
            if !amountRaw.isEmpty {
                lines.append("\(expandedStart) \(fullForm) \(name) \(dose) — \(amountRaw)".trimmingCharacters(in: .whitespaces))

                if !largeVolumeSolution, let amount = prescription.body.subscriptio.amount {
                    let add = expandedDtdLine(formFullLatin: prescription.body.subscriptio.formFullLatin, amount: amount)
                    if !add.isEmpty {
                        lines.append(add)
                        didAddDtd = true
                    }
                }
            } else {
                lines.append("\(expandedStart) \(fullForm) \(name) \(dose)".trimmingCharacters(in: .whitespaces))

                if let amount = prescription.body.subscriptio.amount {
                    let add = expandedDtdLine(formFullLatin: prescription.body.subscriptio.formFullLatin, amount: amount)
                    if !add.isEmpty {
                        lines.append(add)
                        didAddDtd = true
                    }
                }
            }
        }

        let signa = prescription.signatura.text
        if !signa.isEmpty {
            lines.append("\(didAddDtd ? "Signa:" : "Da. Signa:") \(signa)".trimmingCharacters(in: .whitespaces))
        } else {
            lines.append(didAddDtd ? "Signa:" : "Da. Signa:")
        }

        return lines.joined(separator: "\n")
    }

    static func encodeJSON(prescription: Prescription) -> String {
        let container = PrescriptionContainer(prescription: prescription)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(container), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return ""
    }

    private static func parseDose(_ input: String) -> (value: Double?, unit: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (nil, nil) }

        let pattern = "^(\\d+(?:[\\.,]\\d+)?)\\s*([\\p{L}%]+)?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (nil, nil) }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let m = re.firstMatch(in: trimmed, options: [], range: range) else { return (nil, nil) }
        guard let r1 = Range(m.range(at: 1), in: trimmed) else { return (nil, nil) }
        let num = String(trimmed[r1]).replacingOccurrences(of: ",", with: ".")
        let val = Double(num)

        var unit: String?
        if m.numberOfRanges > 2, let r2 = Range(m.range(at: 2), in: trimmed) {
            let raw = String(trimmed[r2])
            if !raw.isEmpty { unit = raw }
        }

        return (val, unit)
    }

    private static func makeSubscriptioParts(form: RecipeForm, amount: Int?) -> (String, String, String, String) {
        return makeSubscriptioPartsDefault(form: form, amount: amount)
    }

    private static func makeSubscriptioPartsDefault(form: RecipeForm, amount: Int?) -> (String, String, String, String) {
        let n = amount
        let nStr = n.map(String.init) ?? ""

        switch form {
        case .tab:
            return ("in tab.", "in tabulettis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .caps:
            return ("in caps.", "in capsulis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .mdi:
            return ("mdi.", "aerosoli inhalationis dosati", "D. S.", "Da. Signa")
        case .supp:
            return ("supp.", "suppositoriorum", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .amp:
            return ("in amp.", "in ampullis", "D.t.d. N. \(nStr) in amp.", "Da tales doses numero \(nStr) in ampullis")
        case .sol:
            return ("sol.", "solutionis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .solExt:
            return ("sol.ext.", "solutionis", "D. S.", "Da. Signa")
        case .gutt:
            return ("gutt.", "guttarum", "D. S.", "Da. Signa")
        case .sir:
            return ("sir.", "sirupi", "D. S.", "Da. Signa")
        case .susp:
            return ("susp.", "suspensionis", "D. S.", "Da. Signa")
        case .emuls:
            return ("emuls.", "emulsionis", "D. S.", "Da. Signa")
        case .tinct:
            return ("tinct.", "tincturae", "D. S.", "Da. Signa")
        case .spr:
            return ("spr.", "spray", "D. S.", "Da. Signa")
        case .ung:
            return ("ung.", "unguenti", "D. S.", "Da. Signa")
        case .crem:
            return ("crem.", "cremae", "D. S.", "Da. Signa")
        case .gel:
            return ("gel.", "gelii", "D. S.", "Da. Signa")
        case .past:
            return ("past.", "pastae", "D. S.", "Da. Signa")
        case .linim:
            return ("linim.", "linimenti", "D. S.", "Da. Signa")
        case .pulv:
            return ("pulv.", "pulveris", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .lyoph:
            return ("lyoph.", "lyophilisati", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .conc:
            return ("conc.", "concentrati", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        }
    }

    private static func prescriptionFormStrings(form: RecipeForm, amount: Int?) -> (String, String, String, String) {
        let n = amount
        let nStr = n.map(String.init) ?? ""

        switch form {
        case .tab:
            return ("in tab.", "in tabulettis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .caps:
            return ("in caps.", "in capsulis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .mdi:
            return ("mdi.", "aerosoli inhalationis dosati", "D. S.", "Da. Signa")
        case .supp:
            return ("supp.", "suppositoriorum", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .amp:
            return ("in amp.", "in ampullis", "D.t.d. N. \(nStr) in amp.", "Da tales doses numero \(nStr) in ampullis")
        case .sol:
            return ("sol.", "solutionis", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .solExt:
            return ("sol.ext.", "solutionis", "D. S.", "Da. Signa")
        case .gutt:
            return ("gutt.", "guttarum", "D. S.", "Da. Signa")
        case .sir:
            return ("sir.", "sirupi", "D. S.", "Da. Signa")
        case .susp:
            return ("susp.", "suspensionis", "D. S.", "Da. Signa")
        case .emuls:
            return ("emuls.", "emulsionis", "D. S.", "Da. Signa")
        case .tinct:
            return ("tinct.", "tincturae", "D. S.", "Da. Signa")
        case .spr:
            return ("spr.", "spray", "D. S.", "Da. Signa")
        case .ung:
            return ("ung.", "unguenti", "D. S.", "Da. Signa")
        case .crem:
            return ("crem.", "cremae", "D. S.", "Da. Signa")
        case .gel:
            return ("gel.", "gelii", "D. S.", "Da. Signa")
        case .past:
            return ("past.", "pastae", "D. S.", "Da. Signa")
        case .linim:
            return ("linim.", "linimenti", "D. S.", "Da. Signa")
        case .pulv:
            return ("pulv.", "pulveris", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .lyoph:
            return ("lyoph.", "lyophilisati", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        case .conc:
            return ("conc.", "concentrati", "D.t.d. N. \(nStr)", "Da tales doses numero \(nStr)")
        }
    }

    private static func formatDose(_ material: PrescriptionMaterial) -> String {
        if let value = material.dosageValue {
            let unit = (material.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let formatted = formatNumericDoseValue(value, unit: unit)
            if unit.isEmpty {
                return formatted
            }
            if unit.lowercased() == "mg" {
                return formatted
            }
            if unit.lowercased() == "g" {
                // In most Rx patterns, grams unit is omitted after the number.
                return formatted
            }
            return "\(formatted) \(unit)"
        }

        if let raw = material.dosageRaw {
            return normalizeDose(raw).replacingOccurrences(of: ".", with: ",")
        }
        return ""
    }

    private static func formatNumericDoseValue(_ value: Double, unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        var v = value

        if u.lowercased() == "mg" {
            v = v / 1000.0
        }

        let decimals: Int
        if v < 0.001 {
            decimals = 6
        } else if v < 0.01 {
            decimals = 5
        } else if v < 0.1 {
            decimals = 4
        } else if v < 1 {
            decimals = 3
        } else {
            decimals = 2
        }

        var s = String(format: "%.*f", decimals, v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            if s.hasSuffix(".") {
                s.removeLast()
                break
            }
            s.removeLast()
        }
        s = s.replacingOccurrences(of: ".", with: ",")
        return s
    }

    private static func capitalize(_ string: String) -> String {
        return formatDrugName(string)
    }

    private static func formatDrugName(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        if trimmed.contains("\"") || trimmed.contains("«") || trimmed.contains("»") {
            return trimmed
        }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        if parts.isEmpty { return trimmed }

        let lowerParts = parts.map { $0.lowercased(with: Locale(identifier: "en_US_POSIX")) }
        let first = lowerParts[0]
        let firstFormatted = first.prefix(1).uppercased() + first.dropFirst()
        let rest = lowerParts.dropFirst()
        return ([String(firstFormatted)] + rest).joined(separator: " ")
    }
}
