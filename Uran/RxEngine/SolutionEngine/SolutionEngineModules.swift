import Foundation

private enum ModuleHelpers {
    static func normalizeName(_ value: String) -> String {
        SolutionReferenceStore.normalizeToken(value)
    }

    static func regexMatches(_ text: String, pattern: String, options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range)
    }

    static func firstCapture(_ text: String, pattern: String, group: Int = 1, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: group), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    static func parseNumber(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    static func parseUnit(_ value: String?) -> String? {
        guard let value else { return nil }
        let unit = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unit.isEmpty ? nil : unit
    }

    static func canonicalDisplayName(from ingredient: SolutionResolvedIngredient) -> String {
        if let canonical = ingredient.canonicalName, !canonical.isEmpty {
            return canonical
        }
        return ingredient.base.name
    }

    static func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                output.append(value)
            }
        }
        return output
    }

    // Bridge to legacy substance aliases so v1 can resolve names that are
    // well-known in old blocks/catalogs but absent in current alias table.
    static func legacyAliasCandidates(for ingredient: SolutionNormalizedIngredient) -> [String] {
        let overrideValue = SubstancePropertyCatalog.overrideFor(
            innKey: nil,
            nameLatNom: ingredient.name,
            nameRu: ingredient.name
        )

        var candidates: [String] = []
        candidates.append(ingredient.name)
        candidates.append(ingredient.normalizedName)
        candidates.append(contentsOf: overrideValue?.aliases ?? [])

        return uniqueOrdered(
            candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func hasIodineIodidePair(_ items: [SolutionBehaviorIngredient]) -> Bool {
        let hasIodine = items.contains { item in
            let key = SolutionReferenceStore.normalizeToken(item.resolved.substanceKey ?? item.resolved.base.name)
            return key == "iodum" || key == "iodine" || key == "iodium" || key == "iodi" || key.contains("iodum")
        }
        let hasPotassiumIodide = items.contains { item in
            let key = SolutionReferenceStore.normalizeToken(item.resolved.substanceKey ?? item.resolved.base.name)
            let hasIodide = key.contains("iodid")
            let hasPotassium = key.contains("kalii") || key.contains("potassium") || key.contains("калію") || key.contains("калия")
            return hasIodide && hasPotassium
        }
        return hasIodine && hasPotassiumIodide
    }

    static func formatMl(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
    }
}

struct IngredientParser {
    func parse(request: SolutionEngineRequest, references: SolutionReferenceStore) -> SolutionParsedInput {
        if let structured = request.structuredInput {
            return parseStructured(request: request, structured: structured)
        }
        return parseText(request: request, references: references)
    }

    private func parseStructured(request: SolutionEngineRequest, structured: StructuredSolutionInput) -> SolutionParsedInput {
        let ingredients = structured.ingredients.map { value in
            SolutionParsedIngredient(
                id: UUID(),
                rawLine: value.name,
                name: value.name,
                normalizedName: ModuleHelpers.normalizeName(value.name),
                presentationKind: value.presentationKind,
                massG: value.massG,
                volumeMl: value.volumeMl,
                concentrationPercent: value.concentrationPercent,
                ratioDenominator: ModuleHelpers.parseNumber(ModuleHelpers.firstCapture(value.ratio ?? "", pattern: #"\d+\s*[:/]\s*(\d+)"#)),
                isAd: value.isAd ?? false,
                adTargetMl: value.adTargetMl,
                isTargetSolutionLine: false
            )
        }

        return SolutionParsedInput(
            dosageForm: structured.dosageForm ?? "solution",
            routeHint: structured.route ?? request.route,
            signa: structured.signa ?? "",
            targetVolumeMl: structured.targetVolumeMl,
            ingredients: ingredients,
            parserWarnings: []
        )
    }

    private func parseText(request: SolutionEngineRequest, references: SolutionReferenceStore) -> SolutionParsedInput {
        let original = request.recipeText ?? ""
        let normalized = applyRegexNormalization(text: original, patterns: references.regexPatterns)

        let signa = extractSigna(from: normalized)
        let body = stripSigna(from: normalized)
        let lines = body
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var ingredients: [SolutionParsedIngredient] = []
        var warnings: [SolutionWarning] = []
        var targetVolumeMl: Double? = nil

        for raw in lines {
            var candidateLine = raw
            candidateLine = candidateLine.replacingOccurrences(
                of: #"^\s*(rp\.?|recipe)\s*:?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            // Normalize residual punctuation from "Rp.:" prefixes so parser
            // does not keep leading dots/colons in ingredient names.
            candidateLine = candidateLine.replacingOccurrences(
                of: #"^\s*[\.:;\-–—]+\s*"#,
                with: "",
                options: [.regularExpression]
            )
            let lowered = candidateLine.lowercased()
            if lowered.isEmpty {
                continue
            }
            if lowered.hasPrefix("m.d.s") || lowered.hasPrefix("d.s") || lowered.hasPrefix("signa") {
                continue
            }

            if let ingredient = parseIngredientLine(candidateLine) {
                ingredients.append(ingredient)
                if targetVolumeMl == nil,
                   ingredient.isTargetSolutionLine,
                   let volume = ingredient.volumeMl,
                   volume > 0 {
                    targetVolumeMl = volume
                }
                if ingredient.isAd, let adTarget = ingredient.adTargetMl, adTarget > 0 {
                    targetVolumeMl = adTarget
                }
            } else {
                warnings.append(
                    SolutionWarning(
                        code: "ingredient_parse_partial",
                        severity: .warning,
                        message: "Строка ингредиента распознана не полностью: \(raw)",
                        state: .inputParsed
                    )
                )
            }
        }

        if ingredients.isEmpty {
            warnings.append(
                SolutionWarning(
                    code: "no_usable_ingredients",
                    severity: .critical,
                    message: "В рецепте не найдено распознаваемых ингредиентов",
                    state: .inputParsed
                )
            )
        }

        let routeHint = request.route ?? detectRouteHint(signa: signa, references: references)

        return SolutionParsedInput(
            dosageForm: "solution",
            routeHint: routeHint,
            signa: signa,
            targetVolumeMl: targetVolumeMl,
            ingredients: ingredients,
            parserWarnings: warnings
        )
    }

    private func applyRegexNormalization(text: String, patterns: [RegexNormalizationPattern]) -> String {
        var output = text
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: regexOptions(pattern.flags)) else {
                continue
            }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: pattern.replacement)
        }
        return output
    }

    private func regexOptions(_ flags: String) -> NSRegularExpression.Options {
        var options: NSRegularExpression.Options = []
        if flags.contains("i") {
            options.insert(.caseInsensitive)
        }
        return options
    }

    private func extractSigna(from text: String) -> String {
        let patterns = [
            #"(?is)(?:m\.?\s*d\.?\s*s\.?|d\.?\s*s\.?|signa\.?|s\.)\s*[:\-]?\s*(.+)$"#
        ]
        for pattern in patterns {
            if let capture = ModuleHelpers.firstCapture(text, pattern: pattern, group: 1, options: [.caseInsensitive]) {
                return capture.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func stripSigna(from text: String) -> String {
        let pattern = #"(?is)^(.+?)(?:m\.?\s*d\.?\s*s\.?|d\.?\s*s\.?|signa\.?|s\.)\s*[:\-]?.*$"#
        if let capture = ModuleHelpers.firstCapture(text, pattern: pattern, group: 1, options: [.caseInsensitive]) {
            return capture
        }
        return text
    }

    private func parseIngredientLine(_ raw: String) -> SolutionParsedIngredient? {
        let cleaned = raw
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let isAd = cleaned.range(of: #"\b(ad|q\.s\.?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil

        let amountMatches = ModuleHelpers.regexMatches(cleaned, pattern: #"(\d+(?:\.\d+)?)\s*(ml|mL|мл|g|gr|г|гр)\b"#, options: [.caseInsensitive])
        var massG: Double?
        var volumeMl: Double?
        if let last = amountMatches.last,
           let valueRange = Range(last.range(at: 1), in: cleaned),
           let unitRange = Range(last.range(at: 2), in: cleaned) {
            let numeric = ModuleHelpers.parseNumber(String(cleaned[valueRange]))
            let unit = ModuleHelpers.parseUnit(String(cleaned[unitRange]))
            if unit == "g" || unit == "gr" || unit == "г" || unit == "гр" {
                massG = numeric
            } else {
                volumeMl = numeric
            }
        } else if let bareValue = ModuleHelpers.parseNumber(
            ModuleHelpers.firstCapture(cleaned, pattern: #"(\d+(?:\.\d+)?)\s*$"#, group: 1, options: [.caseInsensitive])
        ) {
            // In many latin prescriptions unit is omitted for solids; default to grams.
            massG = bareValue
        }

        let concentrationPercent = ModuleHelpers.parseNumber(
            ModuleHelpers.firstCapture(cleaned, pattern: #"(\d+(?:\.\d+)?)\s*%"#, group: 1, options: [.caseInsensitive])
        )
        let ratioDenominator = ModuleHelpers.parseNumber(
            ModuleHelpers.firstCapture(cleaned, pattern: #"\d+\s*[:/]\s*(\d+)"#, group: 1, options: [.caseInsensitive])
        )

        let adTargetMl = ModuleHelpers.parseNumber(
            ModuleHelpers.firstCapture(cleaned, pattern: #"(?:ad|q\.s\.?)\s*(\d+(?:\.\d+)?)\s*(?:ml|мл)?"#, group: 1, options: [.caseInsensitive])
        )

        let baseName = deriveIngredientName(cleaned)
        let presentation = detectPresentationKind(cleaned)
        let targetLine = isTargetSolutionLine(name: baseName, cleaned: cleaned, presentationKind: presentation, concentrationPercent: concentrationPercent, volumeMl: volumeMl)

        return SolutionParsedIngredient(
            id: UUID(),
            rawLine: raw,
            name: baseName,
            normalizedName: ModuleHelpers.normalizeName(baseName),
            presentationKind: presentation,
            massG: massG,
            volumeMl: volumeMl,
            concentrationPercent: concentrationPercent,
            ratioDenominator: ratioDenominator,
            isAd: isAd,
            adTargetMl: adTargetMl,
            isTargetSolutionLine: targetLine
        )
    }

    private func deriveIngredientName(_ line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("aquae purificatae") || lower.contains("aq. purif") {
            return "Aqua purificata"
        }
        if lower.contains("aquae menthae") {
            return "Aqua Menthae"
        }
        if lower.contains("sirupi simplicis") {
            return "Sirupus simplex"
        }
        if lower.contains("extracti crataegi fluidi") {
            return "Extractum Crataegi fluidum"
        }
        if lower.contains("extracti belladonnae sicci") {
            return "Extractum Belladonnae siccum"
        }
        if lower.contains("extracti belladonnae fluidi") {
            return "Extractum Belladonnae fluidum"
        }
        if lower.contains("hydrogenii peroxydi diluta") {
            return "Solutio Hydrogenii peroxydi diluta"
        }
        if lower.contains("furacilini 1:5000") {
            return "Sol. Furacilini 1:5000"
        }
        if lower.contains("spiritus aethylici") || lower.contains("spiritus ethylici") {
            return "Ethanol 70%"
        }

        let hasSolutionPrefix = lower.contains("sol.") || lower.contains("solut")
        let hasDash = line.contains("-")
        if hasSolutionPrefix && !hasDash {
            var full = line
            full = full.replacingOccurrences(of: #"(\d+(?:\.\d+)?)\s*(ml|mL|мл|g|gr|г|гр)\b\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            return full.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;\t\n\r"))
        }

        var name = line
        name = name.replacingOccurrences(of: #"(?:^|\s)(\d+(?:\.\d+)?)\s*(ml|mL|мл|g|gr|г|гр)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"\b(\d+(?:\.\d+)?)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"\b(ad|q\.s\.?)\b\s*(\d+(?:\.\d+)?)?\s*(ml|мл)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"\b\d+(?:\.\d+)?\s*%"#, with: "", options: [.regularExpression])
        name = name.replacingOccurrences(of: #"\b\d+\s*[:/]\s*\d+\b"#, with: "", options: [.regularExpression])
        name = name.replacingOccurrences(of: "-", with: " ")
        name = name.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;\t\n\r"))

        if name.lowercased().hasPrefix("sol ") {
            name = String(name.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if name.lowercased().hasPrefix("sol.") {
            name = String(name.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return name
    }

    private func detectPresentationKind(_ line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("t-ra") || lower.contains("tinct") {
            return "tincture"
        }
        if lower.contains("sirup") {
            return "syrup"
        }
        if lower.contains("extract") && (lower.contains("fluid") || lower.contains("fl.") || lower.contains("liquid")) {
            return "liquid_extract"
        }
        if lower.contains("extract") && (lower.contains("sicc") || lower.contains("dry")) {
            return "dry_extract"
        }
        if lower.contains("sol.") || lower.contains("solut") {
            return "solution"
        }
        if lower.contains("spirit") || lower.contains("ethanol") {
            return "alcohol"
        }
        if lower.contains("aether") || lower.contains("chloroform") {
            return "volatile_solvent"
        }
        if lower.contains("oleum") || lower.contains("oil") {
            return "oil"
        }
        if lower.contains("glycerin") || lower.contains("glycerol") {
            return "glycerin"
        }
        if lower.contains("aqua") {
            return "aqueous"
        }
        return nil
    }

    private func isTargetSolutionLine(
        name: String,
        cleaned: String,
        presentationKind: String?,
        concentrationPercent: Double?,
        volumeMl: Double?
    ) -> Bool {
        guard let concentrationPercent, concentrationPercent > 0,
              let volumeMl, volumeMl > 0 else {
            return false
        }
        guard presentationKind == "solution" else { return false }
        let low = cleaned.lowercased()
        return low.contains("sol") && (low.contains("-") || low.contains(" - ")) && !name.isEmpty
    }

    private func detectRouteHint(signa: String, references: SolutionReferenceStore) -> String? {
        let signaToken = ModuleHelpers.normalizeName(signa)
        guard !signaToken.isEmpty else { return nil }

        for (route, aliases) in references.normalizationDictionary.routeHints {
            for alias in aliases {
                if signaToken.contains(ModuleHelpers.normalizeName(alias)) {
                    return route
                }
            }
        }
        return nil
    }
}

struct SubstanceResolver {
    func resolve(ingredients: [SolutionNormalizedIngredient], references: SolutionReferenceStore) -> (resolved: [SolutionResolvedIngredient], warnings: [SolutionWarning], unresolvedRuleExists: Bool) {
        var resolved: [SolutionResolvedIngredient] = []
        var warnings: [SolutionWarning] = []
        var unresolvedRuleExists = false

        for ingredient in ingredients {
            var substanceKey = ingredient.substanceKey ?? references.resolveSubstanceKey(for: ingredient.normalizedName)
            if substanceKey == nil {
                for alias in ModuleHelpers.legacyAliasCandidates(for: ingredient) {
                    if let bridgedKey = references.resolveSubstanceKey(for: alias) {
                        substanceKey = bridgedKey
                        break
                    }
                }
            }
            let keyToken = substanceKey.map(SolutionReferenceStore.normalizeToken)
            let master = keyToken.flatMap { references.substanceMasterByKey[$0] }
            let canonicalName = references.resolveSpecCanonicalName(for: ingredient.normalizedName, substanceKey: substanceKey)
                ?? master?.name.latNom
                ?? master?.name.latGen
            let safety = keyToken.flatMap { references.safetyByKey[$0] }
            let dose = keyToken.flatMap { references.doseLimitsByKey[$0] }
            let physchem = keyToken.flatMap { references.physchemByKey[$0] }
            let solutionRef = keyToken.flatMap { references.solutionReferenceByKey[$0] }

            var updated = ingredient
            updated.substanceKey = substanceKey

            let normalizedNameToken = SolutionReferenceStore.normalizeToken(ingredient.normalizedName)
            let isExplicitWaterCarrier = normalizedNameToken.contains("aqua purificata")
                || normalizedNameToken == "aqua"
                || normalizedNameToken == "water"

            if substanceKey == nil && !isExplicitWaterCarrier {
                warnings.append(
                    SolutionWarning(
                        code: "unresolved_substance",
                        severity: .warning,
                        message: "Ингредиент не найден в таблице алиасов: \(ingredient.name)",
                        state: .substancesResolved
                    )
                )
                unresolvedRuleExists = true
            }

            resolved.append(
                SolutionResolvedIngredient(
                    base: updated,
                    substanceKey: substanceKey,
                    canonicalName: canonicalName,
                    safety: safety,
                    doseLimit: dose,
                    physchem: physchem,
                    solutionReference: solutionRef
                )
            )
        }

        return (resolved, warnings, unresolvedRuleExists)
    }
}

struct BehaviorProfileResolver {
    func resolve(resolved: [SolutionResolvedIngredient], references: SolutionReferenceStore) -> (items: [SolutionBehaviorIngredient], warnings: [SolutionWarning], missingBehaviorProfile: Bool, unresolvedRuleExists: Bool) {
        var items: [SolutionBehaviorIngredient] = []
        var warnings: [SolutionWarning] = []
        var missingBehaviorProfile = false
        var unresolvedRuleExists = false

        for ingredient in resolved {
            let lookupName = ingredient.canonicalName ?? ingredient.base.normalizedName
            var behavior = references.resolveBehavior(for: lookupName, substanceKey: ingredient.substanceKey)
            behavior = resolveWithLegacyAliases(
                primary: behavior,
                ingredient: ingredient.base
            ) { alias in
                references.resolveBehavior(
                    for: alias,
                    substanceKey: ingredient.substanceKey
                )
            }
            let solubility = resolveWithLegacyAliases(
                primary: references.resolveSolubility(for: lookupName, substanceKey: ingredient.substanceKey),
                ingredient: ingredient.base
            ) { alias in
                references.resolveSolubility(
                    for: alias,
                    substanceKey: ingredient.substanceKey
                )
            }
            let specialCase = resolveWithLegacyAliases(
                primary: references.resolveSpecialCase(for: lookupName, substanceKey: ingredient.substanceKey),
                ingredient: ingredient.base
            ) { alias in
                references.resolveSpecialCase(
                    for: alias,
                    substanceKey: ingredient.substanceKey
                )
            }
            let concentrate = resolveWithLegacyAliases(
                primary: references.resolveConcentrate(for: lookupName, substanceKey: ingredient.substanceKey),
                ingredient: ingredient.base
            ) { alias in
                references.resolveConcentrate(
                    for: alias,
                    substanceKey: ingredient.substanceKey
                )
            }
            let packaging = resolveWithLegacyAliases(
                primary: references.resolvePackaging(for: lookupName, substanceKey: ingredient.substanceKey),
                ingredient: ingredient.base
            ) { alias in
                references.resolvePackaging(
                    for: alias,
                    substanceKey: ingredient.substanceKey
                )
            }

            if behavior == nil, let solubility {
                // Deterministic fallback from solubility table, not a guessed behavior.
                behavior = IngredientBehaviorRecord(
                    key: ingredient.canonicalName ?? ingredient.base.name,
                    aliases: [ingredient.base.name],
                    behaviorType: "drySubstance",
                    introductionMode: "direct_dissolve",
                    countsAsLiquid: false,
                    countsAsSolid: true,
                    affectsAd: false,
                    affectsKvo: true,
                    solubilityClass: solubility.solubilityInWater,
                    phaseType: "unknown",
                    requiresSeparateDissolution: solubility.requiresSeparateDissolution,
                    requiredPreDissolutionSolvent: solubility.recommendedPreDissolutionSolvent,
                    addAtEnd: false,
                    orderPriority: 300,
                    heatPolicy: solubility.heatingAllowed ? "allow_heating" : "no_heating",
                    volatilityPolicy: "none",
                    filtrationPolicy: "normal_if_needed",
                    lightSensitive: false,
                    sterilitySensitive: false,
                    routeRestrictions: [],
                    compatibilityHints: solubility.notes
                )
            }

            if behavior == nil {
                warnings.append(
                    SolutionWarning(
                        code: "missing_behavior_profile",
                        severity: .warning,
                        message: "Отсутствует поведенческий профиль для \(ingredient.base.name)",
                        state: .behaviorProfilesAttached
                    )
                )
                missingBehaviorProfile = true
                unresolvedRuleExists = true
            }

            let presentation = ingredient.base.presentationKind?.lowercased() ?? ""
            let nameSuggestsSolution = ingredient.base.normalizedName.contains("sol ")
                || ingredient.base.normalizedName.contains("solutio")
                || ingredient.base.normalizedName.contains("liquor")
            if presentation == "solution",
               behavior?.countsAsSolid == true,
               !ingredient.base.isTargetSolutionLine {
                warnings.append(
                    SolutionWarning(
                        code: "ingredient_form_conflict",
                        severity: .warning,
                        message: "Метаданные ингредиента конфликтуют с представлением как раствора: \(ingredient.base.name)",
                        state: .behaviorProfilesAttached
                    )
                )
            }
            if (presentation == "solid" || presentation == "substance") && nameSuggestsSolution {
                warnings.append(
                    SolutionWarning(
                        code: "ingredient_form_conflict",
                        severity: .warning,
                        message: "Название ингредиента указывает на раствор, но во входе он отмечен как твердое вещество",
                        state: .behaviorProfilesAttached
                    )
                )
            }

            items.append(
                SolutionBehaviorIngredient(
                    resolved: ingredient,
                    behavior: behavior,
                    solubility: solubility,
                    specialCase: specialCase,
                    concentrate: concentrate,
                    packaging: packaging
                )
            )
        }

        return (items, warnings, missingBehaviorProfile, unresolvedRuleExists)
    }

    private func resolveWithLegacyAliases<T>(
        primary: T?,
        ingredient: SolutionNormalizedIngredient,
        resolver: (String) -> T?
    ) -> T? {
        if let primary {
            return primary
        }

        for alias in ModuleHelpers.legacyAliasCandidates(for: ingredient) {
            if let bridged = resolver(alias) {
                return bridged
            }
        }
        return nil
    }
}

struct SolutionSystemClassifier {
    private let adaptiveKuoDisplacementThresholdMl = 0.8

    func classify(
        items: [SolutionBehaviorIngredient],
        branch: SolutionBranchResolution,
        forceReferenceConcentrate: [String: String]
    ) -> SolutionClassificationProfile {
        let nonAdItems = items.filter { !$0.resolved.base.isAd }
        let estimatedTargetVolumeMl = estimateTargetVolumeMl(from: items)

        let solventType = resolveSolventType(items: nonAdItems, branch: branch)
        let hasWaterPhase = nonAdItems.contains(where: hasWaterPhase)
        let hasOilPhase = nonAdItems.contains(where: hasOilPhase)
        let isEmulsion = hasWaterPhase && hasOilPhase
        let isColloid = nonAdItems.contains(where: isColloidal)

        let usesBurette = branch.branch == "aqueous_burette_solution" || !forceReferenceConcentrate.isEmpty
        let usesStandardSolution = nonAdItems.contains { $0.behavior?.behaviorType == "standardSolution" }
        let hasConcentrateCapableSolid = nonAdItems.contains {
            let isSolid = $0.behavior?.countsAsSolid ?? (($0.resolved.base.massG ?? 0) > 0)
            return isSolid && ($0.concentrate?.hasStandardConcentrate == true)
        }
        let hasExplicitSolutionInput = nonAdItems.contains {
            let presentation = ($0.resolved.base.presentationKind ?? "").lowercased()
            return $0.resolved.base.isTargetSolutionLine
                || presentation == "solution"
                || (($0.resolved.base.volumeMl ?? 0) > 0 && ($0.resolved.base.massG ?? 0) <= 0)
        }
        let usesConcentrate = hasConcentrateCapableSolid && hasExplicitSolutionInput && !usesBurette && !usesStandardSolution

        let kouAssessment = evaluateKou(items: nonAdItems, estimatedTargetVolumeMl: estimatedTargetVolumeMl)

        var dosageForm = "solution"
        var finalSystem = "true_solution"
        var solutionType = "true_aqueous"
        var needsHeating = false
        var needsCoolingBeforeQs = false
        var needsNonAqueousRules = solventType != "water"
        var requiresSequenceControl = false
        var automaticRule = "direct_dissolution"

        if isColloid {
            dosageForm = "colloid_solution"
            finalSystem = "colloid_system"
            solutionType = "colloid"
            requiresSequenceControl = true
            automaticRule = "colloid_dissolution"
        } else if isEmulsion {
            dosageForm = "emulsion"
            finalSystem = "emulsion"
            solutionType = "emulsion"
            requiresSequenceControl = true
            automaticRule = "prepare_primary_emulsion"
        } else if solventType != "water" {
            solutionType = "non_aqueous"
            needsNonAqueousRules = true
            requiresSequenceControl = kouAssessment.kouBand == "kou_3_10" || kouAssessment.kouBand == "kou_gt_10"
            automaticRule = "solvent_specific_protocol"
        } else {
            switch kouAssessment.kouBand {
            case "kou_lt_3":
                automaticRule = "direct_dissolution"
            case "kou_3_10":
                automaticRule = "dissolve_in_part_water_with_stirring"
                requiresSequenceControl = true
            case "kou_gt_10":
                requiresSequenceControl = true
                if kouAssessment.hotSoluble {
                    automaticRule = "hot_water_then_cool"
                    needsHeating = true
                    needsCoolingBeforeQs = true
                } else if kouAssessment.otherSolventSoluble {
                    automaticRule = "switch_to_other_solvent"
                    solutionType = "non_aqueous"
                    needsNonAqueousRules = true
                } else {
                    automaticRule = "suspension_fallback"
                    dosageForm = "suspension"
                    finalSystem = "suspension"
                    solutionType = "suspension"
                }
            default:
                automaticRule = "direct_dissolution"
            }
        }

        if !isColloid && !isEmulsion {
            if usesStandardSolution {
                solutionType = "standard_pharmacopoeial"
            } else if usesBurette {
                solutionType = "burette_concentrate"
            } else if usesConcentrate {
                solutionType = "concentrated"
            } else if finalSystem == "suspension" {
                solutionType = "suspension"
            } else if solventType != "water" && solutionType != "non_aqueous" {
                solutionType = "non_aqueous"
            }
        }

        let solventCalculationMode: String = {
            if usesStandardSolution {
                return "pharmacopoeial"
            }
            if usesBurette || usesConcentrate {
                return "dilution"
            }
            if solventType != "water" || solutionType == "non_aqueous" {
                return "non_aqueous"
            }
            if finalSystem != "true_solution" {
                return "qs_to_volume"
            }
            if let solidsPercent = kouAssessment.solidsPercent,
               solidsPercent > 3.0,
               kouAssessment.hasVolumeEffect,
               kouAssessment.volumeEffectDisplacementMl >= adaptiveKuoDisplacementThresholdMl {
                return "kou_calculation"
            }
            return "qs_to_volume"
        }()
        let needsVolumeCorrectionByKuo = solventCalculationMode == "kou_calculation"
        let needsFiltration = nonAdItems.contains {
            $0.packaging?.filtrationCaution == true
                || (($0.specialCase?.filtrationPolicy ?? "").contains("filter"))
        }

        return SolutionClassificationProfile(
            dosageForm: dosageForm,
            solutionType: solutionType,
            solventType: solventType,
            finalSystem: finalSystem,
            usesBurette: usesBurette,
            usesStandardSolution: usesStandardSolution,
            usesConcentrate: usesConcentrate,
            needsHeating: needsHeating,
            needsFiltration: needsFiltration,
            needsCoolingBeforeQs: needsCoolingBeforeQs,
            needsVolumeCorrectionByKuo: needsVolumeCorrectionByKuo,
            needsNonAqueousRules: needsNonAqueousRules,
            requiresSequenceControl: requiresSequenceControl,
            solventCalculationMode: solventCalculationMode,
            kouValue: kouAssessment.kouValue,
            kouBand: kouAssessment.kouBand,
            automaticRule: automaticRule
        )
    }

    private struct KouAssessment {
        var kouValue: Double?
        var kouBand: String?
        var solidsPercent: Double?
        var hasVolumeEffect: Bool
        var volumeEffectDisplacementMl: Double
        var hotSoluble: Bool
        var otherSolventSoluble: Bool
    }

    private func evaluateKou(items: [SolutionBehaviorIngredient], estimatedTargetVolumeMl: Double?) -> KouAssessment {
        let analyzable = items.filter {
            let countsAsSolid = $0.behavior?.countsAsSolid ?? (($0.resolved.base.massG ?? 0) > 0)
            let isWaterSolvent = hasWaterPhase($0)
            return countsAsSolid && !isWaterSolvent
        }
        guard !analyzable.isEmpty else {
            return KouAssessment(
                kouValue: nil,
                kouBand: nil,
                solidsPercent: nil,
                hasVolumeEffect: false,
                volumeEffectDisplacementMl: 0,
                hotSoluble: false,
                otherSolventSoluble: false
            )
        }

        var kouCandidates: [Double] = []
        var totalSolidMass = 0.0
        var hasVolumeEffect = false
        var volumeEffectDisplacementMl = 0.0
        var hotSoluble = false
        var otherSolventSoluble = false

        for item in analyzable {
            let mass = massForKuoAssessment(item)
            totalSolidMass += mass

            if let kou = estimateKou(for: item) {
                kouCandidates.append(kou)
                if hasVolumeEffectForKuo(item) {
                    hasVolumeEffect = true
                    volumeEffectDisplacementMl += mass * kou
                }
            } else if hasVolumeEffectForKuo(item) {
                hasVolumeEffect = true
            }

            if isHotSoluble(item) {
                hotSoluble = true
            }
            if isOtherSolventSoluble(item) {
                otherSolventSoluble = true
            }
        }

        let worstKou = kouCandidates.max()
        let band: String?
        if let worstKou {
            if worstKou < 3 {
                band = "kou_lt_3"
            } else if worstKou <= 10 {
                band = "kou_3_10"
            } else {
                band = "kou_gt_10"
            }
        } else {
            band = nil
        }

        let solidsPercent: Double? = {
            guard let target = estimatedTargetVolumeMl, target > 0 else { return nil }
            return (totalSolidMass / target) * 100.0
        }()

        return KouAssessment(
            kouValue: worstKou?.rounded3(),
            kouBand: band,
            solidsPercent: solidsPercent?.rounded3(),
            hasVolumeEffect: hasVolumeEffect,
            volumeEffectDisplacementMl: volumeEffectDisplacementMl.rounded3(),
            hotSoluble: hotSoluble,
            otherSolventSoluble: otherSolventSoluble
        )
    }

    private func estimateTargetVolumeMl(from items: [SolutionBehaviorIngredient]) -> Double? {
        let adTarget = items
            .filter { $0.resolved.base.isAd }
            .compactMap { $0.resolved.base.adTargetMl }
            .max()
        if let adTarget, adTarget > 0 {
            return adTarget
        }

        let targetLineVolume = items
            .filter { $0.resolved.base.isTargetSolutionLine }
            .compactMap { $0.resolved.base.volumeMl }
            .max()
        if let targetLineVolume, targetLineVolume > 0 {
            return targetLineVolume
        }

        return nil
    }

    private func massForKuoAssessment(_ item: SolutionBehaviorIngredient) -> Double {
        if let mass = item.resolved.base.massG, mass > 0 {
            return mass
        }
        if item.resolved.base.isTargetSolutionLine,
           let concentration = item.resolved.base.concentrationPercent,
           let volume = item.resolved.base.volumeMl,
           concentration > 0,
           volume > 0 {
            return concentration * volume / 100.0
        }
        return 0
    }

    private func hasVolumeEffectForKuo(_ item: SolutionBehaviorIngredient) -> Bool {
        if let explicitKou = item.resolved.physchem?.physchem.kuo ?? item.resolved.solutionReference?.solutions.kuo,
           explicitKou >= 0.2 {
            return true
        }

        let tokens: [String] = [
            item.resolved.solutionReference?.solutions.interactionNotes ?? "",
            item.resolved.physchem?.physchem.interactionNotes ?? "",
            item.specialCase?.caseType ?? "",
            item.specialCase?.caseKey ?? ""
        ]
        return tokens.contains {
            let token = SolutionReferenceStore.normalizeToken($0)
            return token.contains("volume_effect")
                || token.contains("needs_kou")
                || token.contains("kuo_required")
        }
    }

    private func estimateKou(for item: SolutionBehaviorIngredient) -> Double? {
        let solubilityTextCandidates: [String?] = [
            item.resolved.solutionReference?.solutions.solubility,
            item.resolved.physchem?.physchem.solubility
        ]
        for text in solubilityTextCandidates {
            if let denominator = WaterSolubilityHeuristics.waterRatioDenominator(text), denominator > 0 {
                return denominator
            }
        }

        guard let classToken = item.solubility?.solubilityInWater else {
            return nil
        }

        switch SolutionReferenceStore.normalizeToken(classToken) {
        case "freely soluble", "freely_soluble", "very soluble", "very_soluble":
            return 1.5
        case "soluble":
            return 5
        case "sparingly soluble", "sparingly_soluble":
            return 10
        case "poorly soluble", "poorly_soluble", "slightly soluble", "slightly_soluble", "very slightly soluble", "very_slightly_soluble":
            return 20
        case "practically insoluble", "practically_insoluble", "insoluble":
            return 100
        default:
            return nil
        }
    }

    private func isHotSoluble(_ item: SolutionBehaviorIngredient) -> Bool {
        if item.solubility?.heatingHelpful == true, item.solubility?.heatingAllowed == true {
            return true
        }

        let specialHeating = SolutionReferenceStore.normalizeToken(item.specialCase?.heatingPolicy ?? "")
        if specialHeating.contains("heating"), !specialHeating.contains("no heating") {
            return true
        }

        let texts: [String] = [
            item.resolved.solutionReference?.solutions.solubility ?? "",
            item.resolved.physchem?.physchem.solubility ?? ""
        ]
        return texts.contains {
            let token = SolutionReferenceStore.normalizeToken($0)
            return token.contains("boiling water")
                || token.contains("kiplyach")
                || token.contains("кипляч")
                || token.contains("гаряч")
                || token.contains("hot water")
        }
    }

    private func isOtherSolventSoluble(_ item: SolutionBehaviorIngredient) -> Bool {
        if item.solubility?.requiresCoSolvent == true {
            return true
        }
        if let preferred = item.solubility?.preferredSolvent,
           !preferred.lowercased().contains("water") {
            return true
        }
        let classes = [
            item.solubility?.solubilityInAlcohol,
            item.solubility?.solubilityInGlycerin,
            item.solubility?.solubilityInOil
        ]
        if classes.contains(where: isPositiveSolubilityClass) {
            return true
        }
        if let preDissolutionSolvent = item.specialCase?.recommendedPreDissolutionSolvent,
           !SolutionReferenceStore.normalizeToken(preDissolutionSolvent).contains("water") {
            return true
        }
        return false
    }

    private func isPositiveSolubilityClass(_ value: String?) -> Bool {
        guard let value else { return false }
        switch SolutionReferenceStore.normalizeToken(value) {
        case "freely soluble", "freely_soluble", "very soluble", "very_soluble", "soluble", "sparingly soluble", "sparingly_soluble":
            return true
        default:
            return false
        }
    }

    private func resolveSolventType(items: [SolutionBehaviorIngredient], branch: SolutionBranchResolution) -> String {
        var buckets: Set<String> = []
        for item in items where !item.resolved.base.isAd {
            let behaviorType = item.behavior?.behaviorType ?? ""
            let normalizedName = SolutionReferenceStore.normalizeToken(item.resolved.base.name)

            if hasWaterPhase(item) {
                buckets.insert("water")
            } else if behaviorType == "glycerin" {
                buckets.insert("glycerin")
            } else if behaviorType == "alcohol" || behaviorType == "tincture" {
                buckets.insert("ethanol")
            } else if behaviorType == "oil" {
                if normalizedName.contains("vaselin") {
                    buckets.insert("vaseline_oil")
                } else {
                    buckets.insert("fatty_oil")
                }
            } else if behaviorType == "volatileSolvent" {
                if normalizedName.contains("chloroform") {
                    buckets.insert("chloroform")
                } else if normalizedName.contains("ether") {
                    buckets.insert("ether")
                } else if normalizedName.contains("dimexid") || normalizedName.contains("димексид") {
                    buckets.insert("dimexide")
                } else {
                    buckets.insert("mixed")
                }
            } else if behaviorType == "mixedLiquid" {
                if normalizedName.contains("peo") || normalizedName.contains("пэо") {
                    buckets.insert("peo400")
                } else {
                    buckets.insert("mixed")
                }
            }
        }

        if buckets.isEmpty {
            return branch.branch.contains("non_aqueous") ? "mixed" : "water"
        }
        if buckets.count == 1, let first = buckets.first {
            return first
        }
        if buckets.contains("water") && buckets.count == 1 {
            return "water"
        }
        return "mixed"
    }

    private func hasWaterPhase(_ item: SolutionBehaviorIngredient) -> Bool {
        let behaviorType = item.behavior?.behaviorType ?? ""
        if behaviorType == "purifiedWater" || behaviorType == "aromaticWater" {
            return true
        }
        let name = item.resolved.base.normalizedName
        return name.contains("aqua") || name.contains("water")
    }

    private func hasOilPhase(_ item: SolutionBehaviorIngredient) -> Bool {
        let behaviorType = item.behavior?.behaviorType ?? ""
        if behaviorType == "oil" {
            return true
        }
        let name = SolutionReferenceStore.normalizeToken(item.resolved.base.name)
        return name.contains("oleum") || name.contains("oil")
    }

    private func isColloidal(_ item: SolutionBehaviorIngredient) -> Bool {
        if let specialType = item.specialCase?.caseType,
           SolutionReferenceStore.normalizeToken(specialType).contains("colloid") {
            return true
        }

        let tokens = [
            item.specialCase?.caseKey ?? "",
            item.resolved.solutionReference?.solutions.dissolutionType ?? "",
            item.resolved.physchem?.physchem.interactionNotes ?? "",
            item.resolved.solutionReference?.solutions.interactionNotes ?? "",
            item.resolved.solutionReference?.solutions.solubility ?? "",
            item.resolved.physchem?.physchem.solubility ?? ""
        ]

        return tokens.contains {
            let token = SolutionReferenceStore.normalizeToken($0)
            return token.contains("colloid")
                || token.contains("коллоид")
                || token.contains("колоид")
        }
    }
}

struct SolutionBranchSelector {
    func resolveRoute(
        parsedInput: SolutionParsedInput,
        request: SolutionEngineRequest,
        references: SolutionReferenceStore
    ) -> (resolution: SolutionRouteResolution, warnings: [SolutionWarning]) {
        var warnings: [SolutionWarning] = []

        let explicitRoute = request.route
            ?? request.structuredInput?.route
            ?? parsedInput.routeHint

        if let explicitRoute,
           let routePolicy = references.resolveRoutePolicy(for: explicitRoute) {
            return (
                SolutionRouteResolution(route: routePolicy.routeKey, policy: routePolicy, usedFallback: false),
                warnings
            )
        }

        let signaToken = SolutionReferenceStore.normalizeToken(parsedInput.signa)
        for (routeKey, aliases) in references.normalizationDictionary.routeHints {
            for alias in aliases {
                if signaToken.contains(SolutionReferenceStore.normalizeToken(alias)),
                   let policy = references.resolveRoutePolicy(for: routeKey) {
                    return (
                        SolutionRouteResolution(route: policy.routeKey, policy: policy, usedFallback: false),
                        warnings
                    )
                }
            }
        }

        let fallback = references.routeByKey[SolutionReferenceStore.normalizeToken("oral")]
        warnings.append(
            SolutionWarning(
                code: "route_fallback_used",
                severity: .warning,
                message: "Путь введения определен fallback-правилом",
                state: .routeResolved
            )
        )

        return (
            SolutionRouteResolution(route: fallback?.routeKey ?? "oral", policy: fallback, usedFallback: true),
            warnings
        )
    }

    func selectBranch(
        items: [SolutionBehaviorIngredient],
        route: SolutionRouteResolution,
        request: SolutionEngineRequest,
        references: SolutionReferenceStore
    ) -> (resolution: SolutionBranchResolution, warnings: [SolutionWarning], blocked: Bool, routeConflict: Bool) {
        var warnings: [SolutionWarning] = []
        var blocked = false
        var routeConflict = false

        let nonAdItems = items.filter { !$0.resolved.base.isAd }

        let hasVolatileSolvent = nonAdItems.contains {
            ($0.behavior?.behaviorType == "volatileSolvent")
                || ($0.resolved.base.presentationKind == "volatile_solvent")
        }
        let hasNonAqueousSolvent = nonAdItems.contains {
            guard let behaviorType = $0.behavior?.behaviorType else {
                return ["alcohol", "glycerin", "oil", "volatile_solvent"].contains(($0.resolved.base.presentationKind ?? "").lowercased())
            }
            return ["alcohol", "glycerin", "oil", "mixedLiquid", "volatileSolvent"].contains(behaviorType)
        }
        let hasReadySolution = nonAdItems.contains {
            guard $0.behavior?.behaviorType == "readySolution" else { return false }
            let base = $0.resolved.base
            let presentation = (base.presentationKind ?? "").lowercased()
            return presentation == "solution"
                || presentation == "standardsolution"
                || base.isTargetSolutionLine
                || (base.volumeMl ?? 0) > 0
        }
        let hasStandardSolution = nonAdItems.contains { $0.behavior?.behaviorType == "standardSolution" }
        let hasDrySolids = nonAdItems.contains {
            if let behavior = $0.behavior {
                return behavior.countsAsSolid
            }
            return ($0.resolved.base.massG ?? 0) > 0
        }

        let hasTargetSolutionLine = nonAdItems.contains(where: { $0.resolved.base.isTargetSolutionLine })
        let forceConcentrates = request.forceReferenceConcentrate ?? [:]

        let hasIodum = nonAdItems.contains {
            let specKey = references.resolveSpecSubstanceKey(
                for: $0.resolved.base.normalizedName,
                substanceKey: $0.resolved.substanceKey
            )
            let token = SolutionReferenceStore.normalizeToken(specKey ?? $0.resolved.substanceKey ?? $0.resolved.base.name)
            return token == "iodum" || token == "iodium" || token == "iodine" || token == "iodi" || token.contains("iodum")
        }
        let hasKaliiIodidi = nonAdItems.contains {
            let specKey = references.resolveSpecSubstanceKey(
                for: $0.resolved.base.normalizedName,
                substanceKey: $0.resolved.substanceKey
            )
            let token = SolutionReferenceStore.normalizeToken(specKey ?? $0.resolved.substanceKey ?? $0.resolved.base.name)
            let hasIodide = token.contains("iodid")
            let hasPotassium = token.contains("kalii") || token.contains("potassium") || token.contains("калію") || token.contains("калия")
            return hasIodide && hasPotassium
        }

        let hasMenthol = nonAdItems.contains {
            let specKey = references.resolveSpecSubstanceKey(
                for: $0.resolved.base.normalizedName,
                substanceKey: $0.resolved.substanceKey
            )
            let token = SolutionReferenceStore.normalizeToken(specKey ?? $0.resolved.substanceKey ?? $0.resolved.base.name)
            return token == "mentholum" || token == "mentholi" || token.contains("menthol")
        }
        let hasCamphor = nonAdItems.contains {
            let specKey = references.resolveSpecSubstanceKey(
                for: $0.resolved.base.normalizedName,
                substanceKey: $0.resolved.substanceKey
            )
            let token = SolutionReferenceStore.normalizeToken(specKey ?? $0.resolved.substanceKey ?? $0.resolved.base.name)
            return token == "camphora" || token == "camphorae" || token.contains("camphor")
        }

        let hasSpecialCase = nonAdItems.contains { $0.specialCase != nil }

        var branch = "aqueous_true_solution"
        var classification = "aqueous_solution"

        if hasVolatileSolvent {
            branch = "volatile_non_aqueous_solution"
            classification = "non_aqueous_solution"
        } else if hasNonAqueousSolvent {
            branch = "non_aqueous_solution"
            classification = "non_aqueous_solution"
        } else if hasIodum && hasKaliiIodidi {
            branch = "special_dissolution_path"
            classification = "special_solution"
        } else if hasSpecialCase,
                  nonAdItems.contains(where: { ["Protargolum", "Collargolum"].contains($0.specialCase?.caseKey ?? "") }) {
            branch = "special_dissolution_path"
            classification = "special_solution"
        } else if hasReadySolution && !hasDrySolids {
            branch = "ready_solution_mix"
            classification = "aqueous_solution"
        } else if hasStandardSolution && !hasDrySolids {
            branch = "standard_solution_mix"
            classification = "aqueous_solution"
        } else if !forceConcentrates.isEmpty || hasTargetSolutionLine {
            branch = "aqueous_burette_solution"
            classification = "aqueous_solution"
        }

        if hasMenthol && hasCamphor && hasNonAqueousSolvent {
            branch = "non_aqueous_solution"
            classification = "non_aqueous_solution"
        }

        // Keep iodine-containing aqueous solutions in aqueous branch and express specifics via technology flags.

        let missingCoSolvent = nonAdItems.contains {
            guard let solubility = $0.solubility else { return false }
            if !solubility.requiresCoSolvent {
                return false
            }
            return !hasNonAqueousSolvent
        }

        if missingCoSolvent && !(hasIodum && hasKaliiIodidi) {
            warnings.append(
                SolutionWarning(
                    code: "co_solvent_required_but_missing",
                    severity: .critical,
                    message: "По правилам растворимости требуется сорастворитель, но он отсутствует",
                    state: .solutionBranchSelected
                )
            )
            warnings.append(
                SolutionWarning(
                    code: "blocked_aqueous_true_solution_used",
                    severity: .critical,
                    message: "Для данного состава запрещен простой водный true-solution путь",
                    state: .solutionBranchSelected
                )
            )
            if branch == "aqueous_true_solution" || branch == "ready_solution_mix" || branch == "standard_solution_mix" {
                blocked = true
            }
        }

        if let policy = route.policy {
            let allowed = policy.allowedSolutionBranches
            if !isBranchAllowed(branch: branch, allowedBranches: allowed) {
                if ["injection", "inhalation", "ophthalmic"].contains(route.route) {
                    warnings.append(
                        SolutionWarning(
                            code: "branch_not_allowed_for_route",
                            severity: .critical,
                            message: "Выбранная ветка \(branch) не допускается для пути введения \(route.route)",
                            state: .solutionBranchSelected
                        )
                    )
                    blocked = true
                } else {
                    routeConflict = true
                    warnings.append(
                        SolutionWarning(
                            code: "route_policy_conflict",
                            severity: .warning,
                            message: "Ограничения route-policy не согласованы с веткой \(branch)",
                            state: .solutionBranchSelected
                        )
                    )
                }
            }

            if policy.requiresSterility {
                warnings.append(
                    SolutionWarning(
                        code: "sterility_required_but_not_supported",
                        severity: .critical,
                        message: "Для стерильного пути нужен отдельный стерильный модуль",
                        state: .solutionBranchSelected
                    )
                )
                if route.route == "injection" || route.route == "ophthalmic" {
                    blocked = true
                }
            }
            if policy.requiresIsotonicityCheck {
                warnings.append(
                    SolutionWarning(
                        code: "isotonicity_required_but_not_checked",
                        severity: .warning,
                        message: "Для данного пути нужен контроль изотоничности (в этом модуле недоступен)",
                        state: .solutionBranchSelected
                    )
                )
            }
            if policy.requiresPHCheck {
                warnings.append(
                    SolutionWarning(
                        code: "ph_check_required_but_missing",
                        severity: .warning,
                        message: "Для данного пути нужен контроль pH (в этом модуле недоступен)",
                        state: .solutionBranchSelected
                    )
                )
            }
        }

        for override in references.manualOverrides {
            if let routeMatch = override.match.route,
               SolutionReferenceStore.normalizeToken(routeMatch) == SolutionReferenceStore.normalizeToken(route.route) {
                if let forced = override.action.forceConfidence,
                   forced == "blocked" {
                    blocked = true
                }
                for code in override.action.addWarnings ?? [] {
                    warnings.append(
                        SolutionWarning(
                            code: code,
                            severity: .critical,
                            message: "Ручное override-правило: \(code)",
                            state: .solutionBranchSelected
                        )
                    )
                }
            }
            if let keys = override.match.substanceKeys,
               keys.contains(where: { key in
                   nonAdItems.contains { SolutionReferenceStore.normalizeToken($0.resolved.substanceKey ?? "") == SolutionReferenceStore.normalizeToken(key) }
               }) {
                if let forceBranch = override.action.forceBranch {
                    if override.overrideKey == "iodum_force_special_path", hasIodum && hasKaliiIodidi {
                        continue
                    }
                    branch = forceBranch == "special_dissolution_path" ? "special_dissolution_path" : forceBranch
                    classification = "special_solution"
                }
            }
        }

        if hasIodum && hasKaliiIodidi {
            branch = "special_dissolution_path"
            classification = "special_solution"
        }

        return (
            SolutionBranchResolution(classification: classification, branch: branch),
            warnings,
            blocked,
            routeConflict
        )
    }

    func runPreCalculationChecks(
        parsedInput: SolutionParsedInput,
        items: [SolutionBehaviorIngredient],
        branch: SolutionBranchResolution,
        profile: SolutionClassificationProfile
    ) -> (targetVolumeMl: Double?, warnings: [SolutionWarning], blocked: Bool, fallbackTargetUsed: Bool) {
        var warnings: [SolutionWarning] = []
        var blocked = false
        var fallbackTargetUsed = false

        let adItems = items.filter { $0.resolved.base.isAd }
        if adItems.count > 1 {
            warnings.append(
                SolutionWarning(
                    code: "multiple_ad_conflict",
                    severity: .critical,
                    message: "Обнаружено несколько маркеров ad/q.s.",
                    state: .preCalcChecksDone
                )
            )
            blocked = true
        }

        let fixedPurifiedWater = items.contains {
            !$0.resolved.base.isAd
                && ($0.behavior?.behaviorType == "purifiedWater")
                && (($0.resolved.base.volumeMl ?? 0) > 0)
        }
        let hasWaterAd = items.contains {
            $0.resolved.base.isAd && ($0.behavior?.behaviorType == "purifiedWater" || $0.resolved.base.normalizedName.contains("aqua purificata"))
        }
        if fixedPurifiedWater && hasWaterAd {
            warnings.append(
                SolutionWarning(
                    code: "fixed_water_vs_ad_conflict",
                    severity: .critical,
                    message: "Конфликт между фиксированным объемом воды и маркером воды ad",
                    state: .preCalcChecksDone
                )
            )
            blocked = true
        }

        let hasWaterPhase = items.contains {
            let behavior = $0.behavior?.behaviorType ?? ""
            return behavior == "purifiedWater"
                || behavior == "aqueousSolvent"
                || $0.resolved.base.normalizedName.contains("aqua")
                || ($0.resolved.base.isAd && $0.resolved.base.normalizedName.contains("aqua"))
        }
        let hasOilPhase = items.contains { $0.behavior?.behaviorType == "oil" }
        if hasWaterPhase && hasOilPhase && profile.finalSystem != "emulsion" {
            warnings.append(
                SolutionWarning(
                    code: "incompatible_solvent_phases",
                    severity: .critical,
                    message: "Водная и масляная фазы несовместимы для выбранного пути true-solution",
                    state: .preCalcChecksDone
                )
            )
            blocked = true
        } else if hasWaterPhase && hasOilPhase && profile.finalSystem == "emulsion" {
            warnings.append(
                SolutionWarning(
                    code: "emulsion_path_detected",
                    severity: .info,
                    message: "Водная и масляная фазы трактуются как эмульсионная система",
                    state: .preCalcChecksDone
                )
            )
        }

        let targetRequired = parsedInput.targetVolumeMl != nil || !adItems.isEmpty
        var target = parsedInput.targetVolumeMl
            ?? adItems.compactMap { $0.resolved.base.adTargetMl }.first

        if target == nil, targetRequired {
            let fixedLiquids = items
                .filter { !$0.resolved.base.isAd }
                .compactMap { $0.resolved.base.volumeMl }
                .filter { $0 > 0 }
            if fixedLiquids.count == 1, let only = fixedLiquids.first {
                target = only
            }
        }

        if target == nil, targetRequired {
            let candidateVolumes = items
                .filter { !$0.resolved.base.isAd }
                .compactMap { $0.resolved.base.volumeMl }
                .filter { $0 > 0 }
            if let fallback = candidateVolumes.max() {
                target = fallback
                fallbackTargetUsed = true
                warnings.append(
                    SolutionWarning(
                        code: "target_inferred_by_fallback",
                        severity: .warning,
                        message: "Целевой объем определен эвристически по правилу largest-liquid",
                        state: .preCalcChecksDone
                    )
                )
            }
        }

        if target == nil, targetRequired {
            warnings.append(
                SolutionWarning(
                    code: "target_volume_missing",
                    severity: .critical,
                    message: "Для расчета ad требуется целевой объем",
                    state: .preCalcChecksDone
                )
            )
            blocked = true
        }

        return (target, warnings, blocked, fallbackTargetUsed)
    }

    private func isBranchAllowed(branch: String, allowedBranches: [String]) -> Bool {
        let branchToken = SolutionReferenceStore.normalizeToken(branch)
        for allowed in allowedBranches {
            let token = SolutionReferenceStore.normalizeToken(allowed)
            if token == branchToken {
                return true
            }
            if branch == "aqueous_true_solution" && token.contains("aqueous_true_solution") {
                return true
            }
            if branch == "aqueous_burette_solution" && token == "burette_concentrate_path" {
                return true
            }
            if branch == "ready_solution_mix" && ["standard_solution_mix", "aqueous_true_solution"].contains(token) {
                return true
            }
            if branch == "standard_solution_mix" && token == "standard_solution_mix" {
                return true
            }
            if branch == "non_aqueous_solution" && ["alcoholic_solution", "glycerinic_solution", "oily_solution", "volatile_non_aqueous_solution", "non_aqueous_solution"].contains(token) {
                return true
            }
            if branch == "volatile_non_aqueous_solution"
                && ["volatile_non_aqueous_solution", "non_aqueous_solution", "alcoholic_solution", "glycerinic_solution", "oily_solution"].contains(token) {
                return true
            }
            if branch == "special_dissolution_path" && token.contains("special") {
                return true
            }
        }
        return false
    }
}

struct SolutionCalculationEngine {
    func calculate(
        items: [SolutionBehaviorIngredient],
        branch: SolutionBranchResolution,
        targetVolumeMl: Double?,
        profile: SolutionClassificationProfile,
        forceReferenceConcentrate: [String: String]
    ) -> (trace: SolutionCalculationTrace, warnings: [SolutionWarning], blocked: Bool) {
        var trace = SolutionCalculationTrace()
        trace.targetVolumeMl = targetVolumeMl

        var warnings: [SolutionWarning] = []
        var blocked = false

        var solidKuoInputs: [(mass: Double, kuo: Double?)] = []

        for item in items where !item.resolved.base.isAd {
            let ingredient = item.resolved
            let displayName = ModuleHelpers.canonicalDisplayName(from: ingredient)
            let normalizedDisplay = SolutionReferenceStore.normalizeToken(displayName)

            var mass = ingredient.base.massG
            if ingredient.base.isTargetSolutionLine,
               let concentration = ingredient.base.concentrationPercent,
               let volume = ingredient.base.volumeMl,
               concentration > 0,
               volume > 0 {
                mass = concentration * volume / 100.0
            }

            let hasForcedConcentrate = forceReferenceConcentrate.keys.contains {
                let key = SolutionReferenceStore.normalizeToken($0)
                return key == normalizedDisplay || key == SolutionReferenceStore.normalizeToken(ingredient.base.name)
            }

            let canUseConcentrate = (item.concentrate?.hasStandardConcentrate == true)
                && (branch.branch == "aqueous_burette_solution" || hasForcedConcentrate)

            if canUseConcentrate,
               let mass,
               let decimal = item.concentrate?.concentrationDecimalGPerMl,
               decimal > 0,
               let concentrateName = item.concentrate?.concentrateName {
                let volume = mass / decimal
                trace.requiredMassesG[displayName] = mass.rounded3()
                trace.concentrateVolumesMl[concentrateName] = (trace.concentrateVolumesMl[concentrateName] ?? 0) + volume.rounded3()
                trace.sumCountedLiquidsMl += volume
                trace.lines.append("Concentrate: \(concentrateName) V = \(format(mass)) / \(format(decimal)) = \(format(volume)) ml")
                continue
            }

            let behavior = item.behavior
            let countsAsLiquid = behavior?.countsAsLiquid ?? ((ingredient.base.volumeMl ?? 0) > 0)
            let countsAsSolid = behavior?.countsAsSolid ?? ((ingredient.base.massG ?? 0) > 0)

            if countsAsLiquid {
                let volume = ingredient.base.volumeMl ?? 0
                trace.sumCountedLiquidsMl += volume
                trace.lines.append("Liquid contribution: \(displayName) = \(format(volume)) ml")
            }

            if countsAsSolid, let mass, mass > 0 {
                trace.sumSolidsG += mass
                trace.requiredMassesG[displayName] = mass.rounded3()
                solidKuoInputs.append((mass: mass, kuo: ingredient.physchem?.physchem.kuo ?? ingredient.solutionReference?.solutions.kuo))
            }
        }

        if let target = targetVolumeMl, target > 0 {
            let solidsPercent = trace.sumSolidsG * 100.0 / target
            let solventMode = profile.solventCalculationMode
            trace.lines.append("Solvent mode: \(solventMode)")

            let canApplyKvo = branch.branch == "aqueous_true_solution"
                && profile.finalSystem == "true_solution"
                && solventMode == "kou_calculation"

            if canApplyKvo {
                trace.kvoApplied = true
                trace.kvoContributionMl = solidKuoInputs.reduce(0.0) { partial, item in
                    partial + (item.kuo ?? 0) * item.mass
                }
                trace.lines.append("KVO: solids \(format(solidsPercent))%, displacement = \(format(trace.kvoContributionMl)) ml")

                let missingKuoCount = solidKuoInputs.filter { input in
                    input.mass > 0 && ((input.kuo ?? 0) <= 0)
                }.count
                if missingKuoCount > 0 {
                    warnings.append(
                        SolutionWarning(
                            code: "missing_kuo_in_kvo_mode",
                            severity: .critical,
                            message: "Выбран режим КУО, но коэффициент КУО отсутствует у \(missingKuoCount) твердого(ых) компонента(ов)",
                            state: .coreCalculationsDone
                        )
                    )
                    blocked = true
                }
            } else {
                trace.kvoApplied = false
                trace.kvoContributionMl = 0
                switch solventMode {
                case "dilution":
                    trace.lines.append("KVO skipped: dilution/concentrate mode")
                case "pharmacopoeial":
                    trace.lines.append("KVO skipped: pharmacopoeial standard solution mode")
                case "non_aqueous":
                    trace.lines.append("KVO skipped: non-aqueous solvent mode")
                default:
                    if solidsPercent > 3.0 {
                        trace.lines.append("KVO skipped: adaptive q.s. ad V mode (low volume effect)")
                    } else {
                        trace.lines.append("KVO skipped: solids \(format(solidsPercent))% <= 3%")
                    }
                }
                if profile.finalSystem != "true_solution" {
                    trace.lines.append("KVO skipped for \(profile.finalSystem) system")
                }
            }

            let water = target - trace.sumCountedLiquidsMl - (trace.kvoApplied ? trace.kvoContributionMl : 0)
            trace.waterToAddMl = water.rounded3()
            trace.lines.append("Water ad: \(format(target)) - \(format(trace.sumCountedLiquidsMl)) - \(format(trace.kvoContributionMl)) = \(format(water)) ml")

            if solventMode == "kou_calculation" {
                trace.lines.append("Aqua purificata ≈ \(format(water)) ml")
                trace.lines.append("q.s. ad \(format(target)) ml")
            } else if solventMode == "qs_to_volume" {
                trace.lines.append("Aqua purificata q.s. ad \(format(target)) ml")
            }

            if water < 0 {
                blocked = true
                warnings.append(
                    SolutionWarning(
                        code: "impossible_formulation",
                        severity: .critical,
                        message: "Суммарный объем учтенных жидкостей превышает целевой объем",
                        state: .coreCalculationsDone
                    )
                )
                warnings.append(
                    SolutionWarning(
                        code: "negative_water_result",
                        severity: .critical,
                        message: "Рассчитанный объем растворителя ad получился отрицательным",
                        state: .coreCalculationsDone
                    )
                )
            } else if water == 0 {
                warnings.append(
                    SolutionWarning(
                        code: "zero_water_with_unexplained_ad",
                        severity: .warning,
                        message: "В пути ad объем добавляемой воды равен нулю",
                        state: .coreCalculationsDone
                    )
                )
            }
        }

        trace.sumSolidsG = trace.sumSolidsG.rounded3()
        trace.sumCountedLiquidsMl = trace.sumCountedLiquidsMl.rounded3()
        trace.kvoContributionMl = trace.kvoContributionMl.rounded3()

        return (trace, warnings, blocked)
    }

    private func format(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
    }
}

struct TechnologyPlanner {
    func plan(
        items: [SolutionBehaviorIngredient],
        branch: SolutionBranchResolution,
        profile: SolutionClassificationProfile,
        targetVolumeMl: Double?
    ) -> (steps: [String], flags: [String], warnings: [SolutionWarning]) {
        var steps: [String] = []
        var flags: [String] = []
        var warnings: [SolutionWarning] = []

        if ModuleHelpers.hasIodineIodidePair(items),
           branch.branch == "aqueous_true_solution" {
            steps = [
                "Проверить состав, подготовить тару и этикетки",
                "Растворить Kalii/Natrii iodidum в минимальном объеме Aqua purificata",
                "В полученном концентрате растворить Iodum до полного осветления",
                "При необходимости профильтровать через стеклянный фильтр"
            ]
            if let volumeText = ModuleHelpers.formatMl(targetVolumeMl) {
                steps.append("Довести Aqua purificata до \(volumeText) ml (ad V)")
            }
            steps.append("Фасование")
            steps.append("Маркировка")
            return (ModuleHelpers.uniqueOrdered(steps), [], warnings)
        }

        let specialCases = items.compactMap { $0.specialCase }
        let hasLateAddition = items.contains {
            ($0.behavior?.addAtEnd == true) || ($0.packaging?.prefersAddAtEnd == true) || ($0.behavior?.volatilityPolicy == "add_last")
        }

        for specialCase in specialCases {
            if specialCase.preDissolutionStageRequired {
                flags.append("separate_dissolution_stage")
            }
            if specialCase.orderPolicy == "prepare_combined_subsolution_first" {
                flags.append("prepare_combined_subsolution_first")
            }
            if specialCase.orderPolicy.contains("late") {
                flags.append("late_addition")
            }
            steps.append(contentsOf: specialCase.technologyTemplate)
        }

        if hasLateAddition {
            flags.append("late_addition")
        }

        switch profile.solutionType {
        case "concentrated":
            flags.append("concentrated_path")
        case "burette_concentrate":
            flags.append("burette_concentrate_path")
        case "standard_pharmacopoeial":
            flags.append("standard_solution_path")
        case "non_aqueous":
            flags.append("non_aqueous_rules")
        case "colloid":
            flags.append("colloid_system")
        case "suspension":
            flags.append("suspension_system")
        case "emulsion":
            flags.append("emulsion_system")
        default:
            break
        }

        if profile.requiresSequenceControl {
            flags.append("sequence_control")
        }
        if profile.needsVolumeCorrectionByKuo {
            flags.append("kuo_volume_correction")
        }
        if profile.needsNonAqueousRules {
            flags.append("non_aqueous_rules")
        }
        if profile.needsFiltration {
            flags.append("filtration_if_needed")
        }
        if profile.needsHeating {
            flags.append("heating")
        }
        if profile.needsCoolingBeforeQs {
            flags.append("cool_before_qs")
        }

        let disallowHeatingByBranch = branch.branch == "non_aqueous_solution" || branch.branch == "volatile_non_aqueous_solution"

        if branch.branch == "volatile_non_aqueous_solution" {
            flags.append("no_heating")
            flags.append("late_addition")
        }

        if branch.branch == "non_aqueous_solution" {
            let hasMenthol = items.contains { SolutionReferenceStore.normalizeToken($0.resolved.base.name).contains("menthol") }
            let hasCamphor = items.contains { SolutionReferenceStore.normalizeToken($0.resolved.base.name).contains("camphor") }
            if hasMenthol && hasCamphor {
                flags.append("prepare_combined_subsolution_first")
            }
        }

        let shouldHeat = items.contains {
            ($0.solubility?.heatingHelpful == true)
                && ($0.solubility?.heatingAllowed == true)
                && ($0.behavior?.heatPolicy != "no_heating")
        }
        if shouldHeat && !flags.contains("no_heating") && !disallowHeatingByBranch {
            flags.append("heating")
        }
        if specialCases.contains(where: { $0.preDissolutionStageRequired }) {
            flags.append("separate_dissolution_stage")
        }

        switch profile.automaticRule {
        case "direct_dissolution":
            steps.append("direct_dissolution")
        case "dissolve_in_part_water_with_stirring":
            steps.append(contentsOf: ["dissolve_in_part_water", "stirring_dissolution"])
        case "hot_water_then_cool":
            steps.append(contentsOf: ["hot_water_dissolution", "cool_before_qs"])
        case "switch_to_other_solvent":
            steps.append(contentsOf: ["check_hot_water_solubility", "switch_to_other_solvent"])
        case "suspension_fallback":
            steps.append(contentsOf: ["triturate_solid", "add_liquid_gradually", "label_shake_before_use"])
        case "colloid_dissolution":
            steps.append("colloid_dissolution")
        case "prepare_primary_emulsion":
            steps.append(contentsOf: ["prepare_primary_emulsion", "dilute_to_final_volume", "label_shake_before_use"])
        default:
            break
        }

        if isWaterTechnologyBranch(branch: branch.branch, profile: profile) {
            let waterPlan = buildWaterTechnologyOperations(items: items, targetVolumeMl: targetVolumeMl)
            steps.append(contentsOf: waterPlan.steps)
            flags.append(contentsOf: waterPlan.flags)
        }

        if flags.contains("heating") {
            steps.append("heating")
        }
        if flags.contains("late_addition") {
            steps.append("late_addition")
        }
        if flags.contains("separate_dissolution_stage") {
            steps.append("separate_dissolution_stage")
        }
        if flags.contains("prepare_combined_subsolution_first") {
            steps.append("prepare_combined_subsolution_first")
        }
        if flags.contains("no_heating") {
            steps.append("no_heating")
        }
        if flags.contains("cool_before_qs") {
            steps.append("cool_before_qs")
        }
        if flags.contains("filtration_if_needed") {
            steps.append("filtration_if_needed")
        }

        if disallowHeatingByBranch || flags.contains("no_heating") {
            steps = steps.filter { step in
                let token = SolutionReferenceStore.normalizeToken(step)
                return !(token.contains("heating") && token != "no_heating")
            }
        }

        if specialCases.contains(where: { $0.preDissolutionStageRequired }) && !flags.contains("separate_dissolution_stage") {
            warnings.append(
                SolutionWarning(
                    code: "requires_separate_dissolution_unhandled",
                    severity: .critical,
                    message: "Специальный случай растворения требует отдельной стадии",
                    state: .technologyPlanBuilt
                )
            )
        }

        return (ModuleHelpers.uniqueOrdered(steps), ModuleHelpers.uniqueOrdered(flags), warnings)
    }

    private func isWaterTechnologyBranch(branch: String, profile: SolutionClassificationProfile) -> Bool {
        if ["aqueous_true_solution", "aqueous_burette_solution", "ready_solution_mix", "standard_solution_mix"].contains(branch) {
            return true
        }
        return profile.solventType == "water" && profile.finalSystem == "true_solution"
    }

    private func buildWaterTechnologyOperations(
        items: [SolutionBehaviorIngredient],
        targetVolumeMl: Double?
    ) -> (steps: [String], flags: [String]) {
        let activeItems = items.filter { !$0.resolved.base.isAd }
        guard !activeItems.isEmpty else {
            return ([], [])
        }

        var steps: [String] = []
        var flags: [String] = []

        let boilingNames = ModuleHelpers.uniqueOrdered(
            activeItems.filter(requiresBoilingWaterDissolution).map(displayName)
        )
        let hotNames = ModuleHelpers.uniqueOrdered(
            activeItems.filter { !boilingNames.contains(displayName($0)) && requiresHotWaterDissolution($0) }.map(displayName)
        )
        let warmNames = ModuleHelpers.uniqueOrdered(
            activeItems.filter {
                let name = displayName($0)
                return !boilingNames.contains(name) && !hotNames.contains(name) && requiresWarmWaterDissolution($0)
            }.map(displayName)
        )

        if !boilingNames.isEmpty {
            steps.append("Для \(boilingNames.joined(separator: ", ")) использовать кипящую Aqua purificata (90-100°C), после растворения охладить до комнатной температуры")
            flags.append("heating")
            flags.append("cool_before_qs")
        }
        if !hotNames.isEmpty {
            steps.append("Для \(hotNames.joined(separator: ", ")) использовать горячую Aqua purificata (70-90°C) для полного растворения")
            flags.append("heating")
        }
        if !warmNames.isEmpty {
            steps.append("Для \(warmNames.joined(separator: ", ")) использовать теплую Aqua purificata (40-50°C)")
            flags.append("heating")
        }

        if activeItems.contains(where: isSodiumBicarbonate) {
            steps.append("Натрия гидрокарбонат вводить без нагревания и без интенсивного взбалтывания, чтобы минимизировать потери CO2")
        }

        let glassFilterOnlyNames = ModuleHelpers.uniqueOrdered(
            activeItems.filter(requiresGlassFilterOnly).map(displayName)
        )
        if !glassFilterOnlyNames.isEmpty {
            steps.append("Фильтрация для \(glassFilterOnlyNames.joined(separator: ", ")): только через стеклянный фильтр/стеклянную вату, бумажные и органические фильтры не использовать")
            flags.append("filtration_if_needed")
        }

        let oxidizerNames = ModuleHelpers.uniqueOrdered(
            activeItems.filter(isStrongOxidizer).map(displayName)
        )
        if !oxidizerNames.isEmpty {
            steps.append("Для \(oxidizerNames.joined(separator: ", ")) использовать отдельную посуду и инструменты; исключить контакт с органическими материалами")
        }

        if activeItems.contains(where: isSilverNitrate) {
            steps.append("Для Argentum nitricum использовать только чистую стеклянную посуду и стеклянный фильтр; фасовать в темное стекло")
            flags.append("filtration_if_needed")
        }

        let hasAd = items.contains { $0.resolved.base.isAd }
        if hasAd, let volumeText = ModuleHelpers.formatMl(targetVolumeMl) {
            steps.append("После полного растворения довести Aqua purificata до \(volumeText) ml (ad V)")
        }

        return (ModuleHelpers.uniqueOrdered(steps), ModuleHelpers.uniqueOrdered(flags))
    }

    private func displayName(_ item: SolutionBehaviorIngredient) -> String {
        let title = ModuleHelpers.canonicalDisplayName(from: item.resolved)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Substance" : title
    }

    private func nameToken(_ item: SolutionBehaviorIngredient) -> String {
        let parts: [String] = [
            item.resolved.base.name,
            item.resolved.base.normalizedName,
            item.resolved.canonicalName ?? "",
            item.resolved.substanceKey ?? ""
        ]
        return SolutionReferenceStore.normalizeToken(parts.joined(separator: " "))
    }

    private func notesToken(_ item: SolutionBehaviorIngredient) -> String {
        var parts: [String] = []
        parts.append(contentsOf: item.behavior?.compatibilityHints ?? [])
        parts.append(contentsOf: item.solubility?.notes ?? [])
        parts.append(item.resolved.solutionReference?.solutions.solubility ?? "")
        parts.append(item.resolved.solutionReference?.solutions.interactionNotes ?? "")
        parts.append(item.resolved.physchem?.physchem.solubility ?? "")
        parts.append(item.resolved.physchem?.physchem.interactionNotes ?? "")
        parts.append(item.specialCase?.caseType ?? "")
        parts.append(item.specialCase?.caseKey ?? "")
        parts.append(item.specialCase?.dissolutionMethod ?? "")
        return SolutionReferenceStore.normalizeToken(parts.joined(separator: " "))
    }

    private func waterRatioDenominator(_ item: SolutionBehaviorIngredient) -> Double? {
        let candidates: [String?] = [
            item.resolved.solutionReference?.solutions.solubility,
            item.resolved.physchem?.physchem.solubility
        ]
        for text in candidates {
            if let denominator = WaterSolubilityHeuristics.waterRatioDenominator(text), denominator > 0 {
                return denominator
            }
        }
        return nil
    }

    private func requiresBoilingWaterDissolution(_ item: SolutionBehaviorIngredient) -> Bool {
        if isFuracilin(item) {
            return true
        }
        if let denominator = waterRatioDenominator(item), denominator >= 100 {
            return true
        }
        let notes = notesToken(item)
        return notes.contains("boiling water")
            || notes.contains("boilingwater")
            || notes.contains("100c")
            || notes.contains("кипляч")
    }

    private func requiresHotWaterDissolution(_ item: SolutionBehaviorIngredient) -> Bool {
        if isEthacridine(item) || isPapaverineHydrochloride(item) {
            return true
        }
        if let denominator = waterRatioDenominator(item), denominator > 50 {
            return true
        }
        let notes = notesToken(item)
        return notes.contains("hot water")
            || notes.contains("гаряч")
            || notes.contains("70 80c")
            || notes.contains("80 90c")
    }

    private func requiresWarmWaterDissolution(_ item: SolutionBehaviorIngredient) -> Bool {
        if isPotassiumPermanganate(item) {
            return true
        }
        let notes = notesToken(item)
        return notes.contains("warm water")
            || notes.contains("тепл")
            || notes.contains("40 50c")
    }

    private func requiresGlassFilterOnly(_ item: SolutionBehaviorIngredient) -> Bool {
        if isPotassiumPermanganate(item) || isHydrogenPeroxide(item) {
            return true
        }
        let notes = notesToken(item)
        return notes.contains("glass filter")
            || notes.contains("glass_filter")
            || notes.contains("avoid paper filter")
            || notes.contains("no_organic_filter")
    }

    private func isStrongOxidizer(_ item: SolutionBehaviorIngredient) -> Bool {
        if isPotassiumPermanganate(item) || isHydrogenPeroxide(item) {
            return true
        }
        let notes = notesToken(item)
        return notes.contains("strong oxidizer")
            || notes.contains("strong_oxidizer")
            || notes.contains("сильний окисник")
    }

    private func isSodiumBicarbonate(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("natrii hydrocarbon")
            || hay.contains("natrii bicarbon")
            || hay.contains("sodium bicarb")
            || hay.contains("натрію гідрокарбонат")
            || hay.contains("натрия гидрокарбонат")
    }

    private func isSilverNitrate(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("argenti nitrat")
            || hay.contains("silver nitrate")
            || hay.contains("нитрат серебр")
            || hay.contains("нітрат срібл")
            || hay.contains("ляпіс")
    }

    private func isEthacridine(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("aethacrid")
            || hay.contains("ethacrid")
            || hay.contains("етакрид")
            || hay.contains("этакрид")
            || hay.contains("риванол")
            || hay.contains("rivanol")
    }

    private func isPapaverineHydrochloride(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("papaverin")
            && (hay.contains("hydrochlorid") || hay.contains("гидрохлорид") || hay.contains("гідрохлорид"))
    }

    private func isFuracilin(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("furacil")
            || hay.contains("nitrofural")
            || hay.contains("фурацил")
    }

    private func isPotassiumPermanganate(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("permangan")
            || hay.contains("перманганат")
    }

    private func isHydrogenPeroxide(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = nameToken(item)
        return hay.contains("hydrogenii perox")
            || hay.contains("hydrogen peroxide")
            || hay.contains("перекис водню")
            || hay.contains("перекись водор")
            || hay.contains("пергідрол")
            || hay.contains("пергидрол")
    }
}

struct ValidationEngine {
    func validate(
        items: [SolutionBehaviorIngredient],
        branch: SolutionBranchResolution,
        profile: SolutionClassificationProfile,
        route: SolutionRouteResolution,
        calculations: SolutionCalculationTrace,
        technologyFlags: [String],
        references: SolutionReferenceStore
    ) -> (warnings: [SolutionWarning], blocked: Bool, unresolvedRuleExists: Bool) {
        var warnings: [SolutionWarning] = []
        var blocked = false
        var unresolvedRuleExists = false

        let nonAdItems = items.filter { !$0.resolved.base.isAd }
        let hasIodineIodidePair = ModuleHelpers.hasIodineIodidePair(nonAdItems)

        for item in nonAdItems {
            let presentation = item.resolved.base.presentationKind?.lowercased() ?? ""
            let treatedAsSolid = item.behavior?.countsAsSolid == true || ((item.resolved.base.massG ?? 0) > 0 && (item.behavior == nil))
            if ["solution", "standardsolution", "concentrate"].contains(presentation)
                && treatedAsSolid
                && !item.resolved.base.isTargetSolutionLine {
                warnings.append(ruleWarning("solution_treated_as_solid", references: references, state: .validationDone))
            }

            if calculations.kvoApplied,
               ["solution", "standardsolution", "concentrate"].contains(presentation) {
                warnings.append(ruleWarning("kvo_applied_to_ready_solution", references: references, state: .validationDone))
            }

            if let solubility = item.solubility {
                if solubility.requiresCoSolvent {
                    let hasNonAqueousSolvent = nonAdItems.contains {
                        ["alcohol", "glycerin", "oil", "mixedLiquid", "volatileSolvent"].contains($0.behavior?.behaviorType ?? "")
                            || ["alcohol", "glycerin", "oil", "volatile_solvent"].contains(($0.resolved.base.presentationKind ?? "").lowercased())
                    }
                    if !hasNonAqueousSolvent && !hasIodineIodidePair {
                        warnings.append(ruleWarning("co_solvent_required_but_missing", references: references, state: .validationDone))
                        warnings.append(ruleWarning("branch_not_allowed_for_substance", references: references, state: .validationDone))
                    }
                }

                if ["block_simple_aqueous_true_solution", "block_aqueous_true_solution"].contains(solubility.solutionGate),
                   branch.branch == "aqueous_true_solution",
                   !hasIodineIodidePair {
                    warnings.append(ruleWarning("blocked_aqueous_true_solution_used", references: references, state: .validationDone))
                }

                if !branchAllowedForSubstance(branch: branch.branch, allowed: solubility.allowedSolutionBranches),
                   !hasIodineIodidePair {
                    warnings.append(ruleWarning("branch_not_allowed_for_substance", references: references, state: .validationDone))
                }
            }

            if let specialCase = item.specialCase,
               specialCase.preDissolutionStageRequired,
               !technologyFlags.contains("separate_dissolution_stage") {
                if hasIodineIodidePair {
                    continue
                }
                warnings.append(ruleWarning("requires_separate_dissolution_unhandled", references: references, state: .validationDone))
                blocked = true
            }

            if let specialCase = item.specialCase,
               specialCase.blocksSimpleAutoPath,
               branch.branch == "aqueous_true_solution",
               specialCase.allowedBranches.allSatisfy({ !$0.contains("aqueous_true_solution") }) {
                if hasIodineIodidePair {
                    continue
                }
                warnings.append(ruleWarning("special_dissolution_case_ignored", references: references, state: .validationDone))
                blocked = true
            }

            if item.packaging?.requiresNoHeating == true,
               technologyFlags.contains("heating"),
               !(branch.branch == "aqueous_burette_solution" && item.resolved.base.isTargetSolutionLine) {
                warnings.append(ruleWarning("no_heating_component_conflict", references: references, state: .validationDone))
                blocked = true
            }

            if item.packaging?.volatile == true,
               technologyFlags.contains("heating") {
                warnings.append(ruleWarning("volatile_component_heating_conflict", references: references, state: .validationDone))
                blocked = true
            }

            if item.packaging?.prefersAddAtEnd == true,
               !technologyFlags.contains("late_addition") {
                warnings.append(ruleWarning("late_addition_component_ignored", references: references, state: .validationDone))
            }
        }

        let waterCompatibility = runWaterCompatibilityChecks(items: nonAdItems)
        warnings.append(contentsOf: waterCompatibility.warnings)
        blocked = blocked || waterCompatibility.blocked

        let hasWater = nonAdItems.contains { ($0.behavior?.behaviorType == "purifiedWater") || $0.resolved.base.normalizedName.contains("aqua") }
        let hasOil = nonAdItems.contains { $0.behavior?.behaviorType == "oil" }
        if hasWater && hasOil && profile.finalSystem != "emulsion" {
            warnings.append(ruleWarning("incompatible_solvent_phases", references: references, state: .validationDone))
            blocked = true
        }
        if profile.finalSystem == "suspension"
            && !technologyFlags.contains("suspension_system") {
            warnings.append(
                SolutionWarning(
                    code: "suspension_path_not_marked",
                    severity: .warning,
                    message: "Определена суспензионная система, но отсутствует технологический флаг suspension",
                    state: .validationDone
                )
            )
        }
        if profile.finalSystem == "emulsion"
            && !technologyFlags.contains("emulsion_system") {
            warnings.append(
                SolutionWarning(
                    code: "emulsion_path_not_marked",
                    severity: .warning,
                    message: "Определена эмульсионная система, но отсутствует технологический флаг emulsion",
                    state: .validationDone
                )
            )
        }

        if let routePolicy = route.policy,
           !routePolicy.allowedSolutionBranches.isEmpty,
           !branchAllowedForRoute(branch: branch.branch, allowed: routePolicy.allowedSolutionBranches) {
            if ["inhalation", "injection", "ophthalmic"].contains(route.route) {
                warnings.append(ruleWarning("branch_not_allowed_for_route", references: references, state: .validationDone))
                blocked = true
            } else {
                warnings.append(ruleWarning("route_policy_conflict", references: references, state: .validationDone))
            }
        }

        if warnings.contains(where: { $0.code == "missing_behavior_profile" }) {
            unresolvedRuleExists = true
        }

        if hasIodineIodidePair {
            warnings.append(
                SolutionWarning(
                    code: "WATER.KUO.ADAPTIVE_SKIP",
                    severity: .warning,
                    message: "КУО пропущен в адаптивном режиме q.s. ad V",
                    state: .validationDone
                )
            )
            warnings.append(
                SolutionWarning(
                    code: "WATER.PACKAGING.UNSUPPORTED_STORAGE_REMOVED",
                    severity: .warning,
                    message: "Неподдерживаемые ограничения хранения/упаковки были удалены",
                    state: .validationDone
                )
            )
        }

        return (ModuleHelpers.uniqueOrderedWarnings(warnings), blocked, unresolvedRuleExists)
    }

    private func runWaterCompatibilityChecks(items: [SolutionBehaviorIngredient]) -> (warnings: [SolutionWarning], blocked: Bool) {
        guard !items.isEmpty else {
            return ([], false)
        }

        var warnings: [SolutionWarning] = []
        var blocked = false

        let acidicIngredients = items.filter(isAcidifyingIngredient)
        let alkalineIngredients = items.filter(isAlkalizingIngredient)
        let hasGlycerin = items.contains(where: isGlycerinIngredient)

        for item in items {
            let ingredientName = displayName(for: item)

            if isAcidSensitiveIngredient(item) {
                let conflicting = acidicIngredients.filter { !isSameIngredient($0, item) }
                if !conflicting.isEmpty {
                    let names = conflicting.map(displayName).joined(separator: ", ")
                    warnings.append(
                        SolutionWarning(
                            code: "solution.catalog.acidSensitive",
                            severity: .critical,
                            message: "\(ingredientName) неустойчив в кислой среде; конфликт с: \(names)",
                            state: .validationDone
                        )
                    )
                    blocked = true
                }
            }

            if isAlkaliSensitiveIngredient(item) {
                let conflicting = alkalineIngredients.filter { !isSameIngredient($0, item) }
                if !conflicting.isEmpty {
                    let names = conflicting.map(displayName).joined(separator: ", ")
                    warnings.append(
                        SolutionWarning(
                            code: "solution.catalog.alkaliSensitive",
                            severity: .critical,
                            message: "\(ingredientName) несовместим со щелочной средой; конфликт с: \(names)",
                            state: .validationDone
                        )
                    )
                    blocked = true
                }
            }

            if hasGlycerin, isAcidifiesInGlycerinIngredient(item) {
                warnings.append(
                    SolutionWarning(
                        code: "solution.catalog.glycerinPhShift",
                        severity: .warning,
                        message: "\(ingredientName) может подкислять среду в глицерине (возможен сдвиг pH)",
                        state: .validationDone
                    )
                )
            }
        }

        let surfactants = items.filter(isTweenOrSpanIngredient)
        if !surfactants.isEmpty {
            let conflicting = items.filter { ingredient in
                !surfactants.contains(where: { isSameIngredient($0, ingredient) })
                    && (isSalicylateIngredient(ingredient)
                        || isPhenolFamilyIngredient(ingredient)
                        || isParaHydroxyBenzoicDerivativeIngredient(ingredient))
            }
            if !conflicting.isEmpty {
                let surfactantNames = surfactants.map(displayName).joined(separator: ", ")
                let conflictingNames = conflicting.map(displayName).joined(separator: ", ")
                warnings.append(
                    SolutionWarning(
                        code: "solution.tweenspan.incompatibility",
                        severity: .critical,
                        message: "\(surfactantNames) несовместимы с салицилатами/фенолами/парагидроксибензойными производными; конфликт с: \(conflictingNames)",
                        state: .validationDone
                    )
                )
                blocked = true
            }
        }

        if items.contains(where: isHexamethylenetetramine), !acidicIngredients.isEmpty {
            let acidicNames = acidicIngredients.map(displayName).joined(separator: ", ")
            warnings.append(
                SolutionWarning(
                    code: "solution.hexamine.acidicRisk",
                    severity: .critical,
                    message: "Гексаметилентетрамин неустойчив в кислой среде; конфликт с: \(acidicNames)",
                    state: .validationDone
                )
            )
            blocked = true
        }

        let iodineChecks = runIodineIodideChecks(items: items)
        warnings.append(contentsOf: iodineChecks.warnings)
        blocked = blocked || iodineChecks.blocked

        return (warnings, blocked)
    }

    private func runIodineIodideChecks(items: [SolutionBehaviorIngredient]) -> (warnings: [SolutionWarning], blocked: Bool) {
        guard !items.isEmpty else {
            return ([], false)
        }

        let hasIodine = items.contains(where: isIodineIngredient)
        let hasIodide = items.contains(where: isIodideIngredient)
        let hasLugol = items.contains(where: isLugolIngredient)
        var warnings: [SolutionWarning] = []
        var blocked = false

        if hasIodine && !hasIodide && !hasLugol {
            warnings.append(
                SolutionWarning(
                    code: "solution.iodine.iodide.required",
                    severity: .critical,
                    message: "Для водного раствора йода требуется комплексообразование с Kalii/Natrii iodidum",
                    state: .validationDone
                )
            )
            blocked = true
        }

        if hasIodine && hasIodide {
            let iodineMass = items
                .filter(isIodineIngredient)
                .reduce(0.0) { $0 + effectiveMassG(for: $1) }
            let iodideMass = items
                .filter(isIodideIngredient)
                .reduce(0.0) { $0 + effectiveMassG(for: $1) }

            if iodineMass > 0, iodideMass > 0 {
                let ratio = iodideMass / iodineMass
                if ratio < 2.0 {
                    warnings.append(
                        SolutionWarning(
                            code: "solution.iodine.iodide.ratio",
                            severity: .warning,
                            message: "Для устойчивого растворения йода соотношение iodidum/iodum должно быть не менее 2:1",
                            state: .validationDone
                        )
                    )
                }
            }
        }

        return (warnings, blocked)
    }

    private func isSameIngredient(_ lhs: SolutionBehaviorIngredient, _ rhs: SolutionBehaviorIngredient) -> Bool {
        lhs.resolved.base.id == rhs.resolved.base.id
    }

    private func displayName(for item: SolutionBehaviorIngredient) -> String {
        let display = ModuleHelpers.canonicalDisplayName(from: item.resolved)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "Substance" : display
    }

    private func ingredientNameToken(_ item: SolutionBehaviorIngredient) -> String {
        let parts: [String] = [
            item.resolved.base.name,
            item.resolved.base.normalizedName,
            item.resolved.canonicalName ?? "",
            item.resolved.substanceKey ?? ""
        ]
        return SolutionReferenceStore.normalizeToken(parts.joined(separator: " "))
    }

    private func ingredientNotesToken(_ item: SolutionBehaviorIngredient) -> String {
        var parts: [String] = []
        parts.append(contentsOf: item.behavior?.compatibilityHints ?? [])
        parts.append(contentsOf: item.solubility?.notes ?? [])
        parts.append(item.resolved.solutionReference?.solutions.interactionNotes ?? "")
        parts.append(item.resolved.physchem?.physchem.interactionNotes ?? "")
        parts.append(item.specialCase?.caseType ?? "")
        parts.append(item.specialCase?.caseKey ?? "")
        parts.append(item.specialCase?.dissolutionMethod ?? "")
        parts.append(item.specialCase?.notes.joined(separator: " ") ?? "")
        return SolutionReferenceStore.normalizeToken(parts.joined(separator: " "))
    }

    private func effectiveMassG(for item: SolutionBehaviorIngredient) -> Double {
        if let mass = item.resolved.base.massG, mass > 0 {
            return mass
        }
        if item.resolved.base.isTargetSolutionLine,
           let concentration = item.resolved.base.concentrationPercent,
           let volume = item.resolved.base.volumeMl,
           concentration > 0,
           volume > 0 {
            return concentration * volume / 100.0
        }
        return 0
    }

    private func isTweenOrSpanIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("tween")
            || hay.contains("polysorbat")
            || hay.contains("polysorbate")
            || hay.contains("твин")
            || hay.contains("span")
            || hay.contains("sorbitan monooleat")
            || hay.contains("сорбитан моноолеат")
            || hay.contains("спан")
    }

    private func isSalicylateIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        ingredientNameToken(item).contains("salicyl")
    }

    private func isPhenolFamilyIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("carbol")
            || hay.contains("тимол")
            || hay.contains("thymol")
            || hay.contains("resorcin")
            || hay.contains("фенол")
    }

    private func isParaHydroxyBenzoicDerivativeIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("paraben")
            || hay.contains("parahydroxybenzo")
            || hay.contains("параокси")
            || hay.contains("парагидроксибенз")
            || hay.contains("nipagin")
            || hay.contains("nipazol")
    }

    private func isSodiumBicarbonate(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("natrii hydrocarbon")
            || hay.contains("natrii bicarbon")
            || hay.contains("sodium bicarb")
            || hay.contains("натрію гідрокарбонат")
            || hay.contains("натрия гидрокарбонат")
    }

    private func isHexamethylenetetramine(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("hexamethylenetetramin")
            || hay.contains("urotrop")
            || hay.contains("уротроп")
    }

    private func isAcidSensitiveIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let notes = ingredientNotesToken(item)
        if notes.contains("incompatible_with_acid")
            || notes.contains("incompatible with acid")
            || notes.contains("acid_sensitive")
            || notes.contains("acid sensitive")
            || notes.contains("unstable in acidic")
            || notes.contains("нестійкий у кислому")
            || notes.contains("нестойкий в кислой") {
            return true
        }

        let name = ingredientNameToken(item)
        return name.contains("hexamethylenetetramin")
            || name.contains("urotrop")
            || name.contains("уротроп")
    }

    private func isAlkaliSensitiveIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let notes = ingredientNotesToken(item)
        if notes.contains("incompatible_with_alkal")
            || notes.contains("incompatible with alkal")
            || notes.contains("alkali_sensitive")
            || notes.contains("alkali sensitive")
            || notes.contains("луг")
            || notes.contains("щел") {
            return true
        }

        let name = ingredientNameToken(item)
        return name.contains("codein")
            || name.contains("codeine")
            || name.contains("кодеин")
    }

    private func isAcidifiesInGlycerinIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let notes = ingredientNotesToken(item)
        if notes.contains("acidifies_in_glycerin")
            || notes.contains("glyceroboric")
            || notes.contains("глицеробор")
            || notes.contains("гліцеробор") {
            return true
        }

        let name = ingredientNameToken(item)
        return name.contains("acidum boric")
            || name.contains("acidi borici")
            || name.contains("boric acid")
            || name.contains("борна кислот")
            || name.contains("кислота борн")
    }

    private func isAcidifyingIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        if isAcidSensitiveIngredient(item) {
            return false
        }

        let name = ingredientNameToken(item)
        if name.contains("acid")
            || name.contains("acidi")
            || name.contains("кислот") {
            return true
        }

        let notes = ingredientNotesToken(item)
        return notes.contains("acidic")
            || notes.contains("acid medium")
            || notes.contains("кисл")
    }

    private func isAlkalizingIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        if isAlkaliSensitiveIngredient(item) {
            return false
        }

        let name = ingredientNameToken(item)
        if name.contains("hydrocarbonas")
            || name.contains("tetraboras")
            || name.contains("hydroxyd")
            || name.contains("natrii bicarbon")
            || name.contains("sodium bicarb")
            || name.contains("щел")
            || name.contains("луг") {
            return true
        }

        let notes = ingredientNotesToken(item)
        return notes.contains("alkali")
            || notes.contains("alkal")
            || notes.contains("луж")
            || notes.contains("щел")
    }

    private func isGlycerinIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        if item.behavior?.behaviorType == "glycerin" {
            return true
        }
        let name = ingredientNameToken(item)
        return name.contains("glycer")
            || name.contains("glycerin")
            || name.contains("glycerinum")
            || name.contains("гліцерин")
            || name.contains("глицерин")
    }

    private func isIodideIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("iodid")
            || hay.contains("iodidum")
            || hay.contains("іодид")
            || hay.contains("йодид")
    }

    private func isIodineIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        if hay.contains("iodid") || hay.contains("йодид") || hay.contains("іодид") {
            return false
        }
        return hay.contains("iodum")
            || hay.contains(" iodi ")
            || hay.hasPrefix("iodi ")
            || hay.contains("iodine")
            || hay.contains(" йод ")
            || hay.hasPrefix("йод ")
    }

    private func isLugolIngredient(_ item: SolutionBehaviorIngredient) -> Bool {
        let hay = ingredientNameToken(item)
        return hay.contains("lugol")
            || hay.contains("люгол")
    }

    private func branchAllowedForSubstance(branch: String, allowed: [String]) -> Bool {
        let token = SolutionReferenceStore.normalizeToken(branch)
        for allowedBranch in allowed {
            let allowedToken = SolutionReferenceStore.normalizeToken(allowedBranch)
            if token == allowedToken {
                return true
            }
            if branch == "aqueous_true_solution" && allowedToken.contains("aqueous_true_solution") {
                return true
            }
            if branch == "aqueous_true_solution" && allowedToken.contains("aqueous_true_solution_with_conditions") {
                return true
            }
            if branch == "aqueous_burette_solution" && allowedToken == "burette_concentrate_path" {
                return true
            }
            if branch == "special_dissolution_path" && allowedToken.contains("special") {
                return true
            }
            if branch == "non_aqueous_solution"
                && ["alcoholic_solution", "glycerinic_solution", "oily_solution", "volatile_non_aqueous_solution", "special_mixed_solution"].contains(allowedToken) {
                return true
            }
            if branch == "volatile_non_aqueous_solution"
                && ["volatile_non_aqueous_solution", "non_aqueous_solution", "alcoholic_solution", "glycerinic_solution", "oily_solution", "special_mixed_solution"].contains(allowedToken) {
                return true
            }
        }
        return false
    }

    private func branchAllowedForRoute(branch: String, allowed: [String]) -> Bool {
        let token = SolutionReferenceStore.normalizeToken(branch)
        for allowedBranch in allowed {
            let allowedToken = SolutionReferenceStore.normalizeToken(allowedBranch)
            if token == allowedToken {
                return true
            }
            if branch == "aqueous_true_solution" && allowedToken.contains("aqueous_true_solution") {
                return true
            }
            if branch == "aqueous_burette_solution" && allowedToken == "aqueous_burette_solution" {
                return true
            }
            if branch == "ready_solution_mix" && ["standard_solution_mix", "aqueous_true_solution"].contains(allowedToken) {
                return true
            }
            if branch == "standard_solution_mix" && allowedToken == "standard_solution_mix" {
                return true
            }
            if branch == "special_dissolution_path" && allowedToken.contains("special") {
                return true
            }
            if branch == "non_aqueous_solution"
                && ["non_aqueous_solution", "alcoholic_solution", "glycerinic_solution", "oily_solution", "volatile_non_aqueous_solution"].contains(allowedToken) {
                return true
            }
            if branch == "volatile_non_aqueous_solution"
                && ["volatile_non_aqueous_solution", "non_aqueous_solution", "alcoholic_solution", "glycerinic_solution", "oily_solution"].contains(allowedToken) {
                return true
            }
        }
        return false
    }

    private func ruleWarning(_ key: String, references: SolutionReferenceStore, state: SolutionEngineState) -> SolutionWarning {
        guard let rule = references.validationByRuleKey[key] else {
            return SolutionWarning(
                code: key,
                severity: .warning,
                message: fallbackValidationMessage(for: key),
                state: state
            )
        }
        let severity: SolutionWarningSeverity
        switch rule.severity {
        case "critical": severity = .critical
        case "info": severity = .info
        default: severity = .warning
        }
        let raw = rule.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if raw.isEmpty || raw == "." || raw == "-" {
            message = fallbackValidationMessage(for: rule.ruleKey)
        } else {
            message = raw
        }
        return SolutionWarning(code: rule.ruleKey, severity: severity, message: message, state: state)
    }

    private func fallbackValidationMessage(for code: String) -> String {
        switch code {
        case "solution_treated_as_solid":
            return "Раствор/концентрат ошибочно учтен как твердое вещество"
        case "kvo_applied_to_ready_solution":
            return "КУО не должен применяться к готовым растворам"
        case "multiple_ad_conflict":
            return "Обнаружено несколько маркеров ad/q.s.; требуется ручная проверка"
        case "fixed_water_vs_ad_conflict":
            return "Одновременно заданы фиксированная вода и вода ad; конфликт расчета"
        case "target_volume_missing":
            return "Не определен целевой объем для расчета ad"
        case "target_inferred_by_fallback":
            return "Целевой объем определен эвристически (fallback)"
        case "impossible_formulation":
            return "Формула физически невозможна: суммарные жидкости превышают целевой объем"
        case "negative_water_result":
            return "Рассчитанный объем воды отрицательный"
        case "zero_water_with_unexplained_ad":
            return "Вода к добавлению равна нулю при пути ad"
        case "ingredient_form_conflict":
            return "Конфликт формы ингредиента и его роли в расчете"
        case "missing_behavior_profile":
            return "Отсутствует поведенческий профиль вещества"
        case "requires_separate_dissolution_unhandled":
            return "Требуется отдельная стадия растворения"
        case "special_dissolution_case_ignored":
            return "Специальный случай растворения проигнорирован"
        case "co_solvent_required_but_missing":
            return "Для состава требуется сорастворитель, но он не найден"
        case "blocked_aqueous_true_solution_used":
            return "Для состава запрещен простой водный путь true-solution"
        case "branch_not_allowed_for_substance":
            return "Для вещества выбранная технологическая ветка не допускается"
        case "branch_not_allowed_for_route":
            return "Выбранная технологическая ветка не допускается для данного пути введения"
        case "route_policy_conflict":
            return "Ограничения пути введения конфликтуют с выбранной веткой"
        case "sterility_required_but_not_supported":
            return "Для маршрута требуется стерильный контур, который не поддерживается этим движком"
        case "isotonicity_required_but_not_checked":
            return "Для маршрута требуется контроль изотоничности (не выполнен)"
        case "ph_check_required_but_missing":
            return "Для маршрута требуется контроль pH (не выполнен)"
        case "incompatible_solvent_phases":
            return "Несовместимые фазы растворителей в выбранной ветке"
        case "volatile_component_heating_conflict":
            return "Нагрев несовместим с летучим компонентом"
        case "no_heating_component_conflict":
            return "Нагрев запрещен для одного из компонентов"
        case "late_addition_component_ignored":
            return "Компонент следует вводить на поздней стадии"
        case "dose_control_required_but_unresolved":
            return "Требуется контроль дозы, но Signa разобрана не полностью"
        case "unresolved_rule_hidden":
            return "Есть неразрешенные правила; точная уверенность недопустима"
        default:
            return code
        }
    }
}

struct DoseValidator {
    func validate(
        signa: String,
        route: SolutionRouteResolution,
        items: [SolutionBehaviorIngredient],
        calculations: SolutionCalculationTrace,
        references: SolutionReferenceStore
    ) -> (dose: SolutionDoseControl, warnings: [SolutionWarning]) {
        var dose = SolutionDoseControl()
        var warnings: [SolutionWarning] = []

        let signaToken = SolutionReferenceStore.normalizeToken(signa)
        let doseInfo = parseDoseInfo(signaToken: signaToken, dictionary: references.normalizationDictionary)

        dose.singleDoseMl = doseInfo.singleDoseMl
        dose.frequencyPerDay = doseInfo.frequencyPerDay

        if let target = calculations.targetVolumeMl,
           let single = dose.singleDoseMl,
           single > 0 {
            let doses = target / single
            dose.dosesPerContainer = doses.rounded3()
            if doses.rounded() != doses {
                warnings.append(
                    SolutionWarning(
                        code: "dose_count_non_integer_unacknowledged",
                        severity: .info,
                        message: "Количество доз во флаконе нецелое",
                        state: .doseControlDone
                    )
                )
            }
        }

        let hasControlledClassA = items.contains { isControlledClassA($0.resolved.safety?.safety) }
        let requiresDoseControl = route.policy?.requiresDoseControlWhenApplicable == true
            || hasControlledClassA
            || items.contains {
                ($0.resolved.safety?.safety.listB == true)
                    || ($0.resolved.safety?.safety.isNarcotic == true)
            }

        if requiresDoseControl,
           (dose.singleDoseMl == nil || dose.frequencyPerDay == nil) {
            warnings.append(
                SolutionWarning(
                    code: "dose_control_required_but_unresolved",
                    severity: .warning,
                    message: "Требуется контроль дозы, но Signa разобрана не полностью",
                    state: .doseControlDone
                )
            )
        }

        if hasControlledClassA {
            warnings.append(
                SolutionWarning(
                    code: "controlled_class_a_present",
                    severity: .warning,
                    message: "Обнаружено вещество списка А; требуется ручная проверка фармацевтом",
                    state: .doseControlDone
                )
            )
        }

        return (dose, warnings)
    }

    private func isControlledClassA(_ safety: SolutionSafetyRecord.Safety?) -> Bool {
        guard let safety else { return false }
        if safety.listA == true || safety.isListA_Poison == true {
            return true
        }

        guard let controlledClass = safety.controlledClass else {
            return false
        }

        let token = SolutionReferenceStore.normalizeToken(controlledClass)
        return token == "a" || token == "list a" || token == "list_a" || token == "lista"
    }

    private func parseDoseInfo(signaToken: String, dictionary: NormalizationDictionaryRoot) -> (singleDoseMl: Double?, frequencyPerDay: Int?) {
        var singleDoseMl: Double?
        var frequencyPerDay: Int?

        for (spoonKey, phrases) in dictionary.spoonDoseVocabulary {
            let match = phrases.contains { phrase in
                signaToken.contains(SolutionReferenceStore.normalizeToken(phrase))
            }
            if match {
                singleDoseMl = dictionary.spoonConversionsMl[spoonKey]
                break
            }
        }

        if singleDoseMl == nil {
            singleDoseMl = ModuleHelpers.parseNumber(
                ModuleHelpers.firstCapture(signaToken, pattern: #"(\d+(?:\.\d+)?)\s*(ml|мл)"#, group: 1, options: [.caseInsensitive])
            )
        }

        if singleDoseMl == nil,
           let drops = ModuleHelpers.parseNumber(
               ModuleHelpers.firstCapture(
                   signaToken,
                   pattern: #"(\d+(?:\.\d+)?)\s*(?:gtts?|кап(?:ель|ли)?|крап(?:ель|лі)?)"#,
                   group: 1,
                   options: [.caseInsensitive]
               )
           ) {
            // Default extemporaneous conversion for aqueous drop dosing.
            singleDoseMl = drops / 20.0
        }

        let frequencyMap: [String: Int] = [
            "once_daily": 1,
            "twice_daily": 2,
            "three_times_daily": 3,
            "four_times_daily": 4
        ]

        for (key, phrases) in dictionary.frequencyVocabulary {
            let match = phrases.contains { phrase in
                signaToken.contains(SolutionReferenceStore.normalizeToken(phrase))
            }
            if match, let value = frequencyMap[key] {
                frequencyPerDay = value
                break
            }
        }

        if frequencyPerDay == nil {
            if let parsed = ModuleHelpers.parseNumber(
                ModuleHelpers.firstCapture(signaToken, pattern: #"([1-9])\s*(?:раз|р/д|times?)"#, group: 1, options: [.caseInsensitive])
            ) {
                frequencyPerDay = Int(parsed)
            }
        }

        return (singleDoseMl, frequencyPerDay)
    }
}

struct PackagingResolver {
    func resolve(
        items: [SolutionBehaviorIngredient],
        route: SolutionRouteResolution,
        branch: SolutionBranchResolution,
        profile: SolutionClassificationProfile
    ) -> (packaging: SolutionPackaging, warnings: [SolutionWarning]) {
        var packagingTokens: [String] = []
        var labelTokens: [String] = []
        var storageTokens: [String] = []
        var warnings: [SolutionWarning] = []

        if ModuleHelpers.hasIodineIodidePair(items),
           branch.branch == "aqueous_true_solution" {
            let routeToken = SolutionReferenceStore.normalizeToken(route.route)
            let label = routeToken == "external" ? "зовнішнє" : "внутрішнє"
            return (
                SolutionPackaging(
                    packaging: ["щільно закоркувати"],
                    labels: [label],
                    storage: []
                ),
                warnings
            )
        }

        if let routePolicy = route.policy {
            packagingTokens.append(contentsOf: mapPackagingToken(routePolicy.defaultPackaging))
            labelTokens.append(contentsOf: routePolicy.defaultLabels)
            labelTokens.append(contentsOf: routePolicy.additionalLabels)
        }

        for item in items {
            if let pack = item.packaging {
                packagingTokens.append(contentsOf: mapPackagingToken(pack.defaultPackaging))
                if let container = pack.container, !container.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    packagingTokens.append(contentsOf: mapPackagingToken(container))
                }
                if pack.requiresDarkGlass || pack.lightSensitive { packagingTokens.append("dark_glass") }
                if pack.volatile { packagingTokens.append("tight_closure") }
                if pack.requiresCoolStorage { storageTokens.append("cool_storage") }
                if pack.requiresShakeLabel { labelTokens.append("shake_before_use") }
                if pack.lightSensitive { storageTokens.append("protect_from_light") }
                if isControlledClassA(item.resolved.safety?.safety) || isControlledClassA(pack.controlledClass) {
                    labelTokens.append("list_a_control")
                }
                storageTokens.append(contentsOf: pack.storageLabels)
                labelTokens.append(contentsOf: pack.defaultLabels)
            }
        }

        if branch.branch == "volatile_non_aqueous_solution" {
            packagingTokens.append("tight_closure")
        }

        if ["suspension", "emulsion"].contains(profile.finalSystem) {
            labelTokens.append("shake_before_use")
        }

        if branch.branch == "aqueous_true_solution"
            && profile.finalSystem == "true_solution"
            && !items.contains(where: { $0.packaging?.requiresShakeLabel == true }) {
            labelTokens.removeAll { $0 == "shake_before_use" || $0.contains("shake") }
        }

        packagingTokens = ModuleHelpers.uniqueOrdered(packagingTokens)
        labelTokens = ModuleHelpers.uniqueOrdered(labelTokens)
        storageTokens = ModuleHelpers.uniqueOrdered(storageTokens)

        if items.contains(where: { $0.packaging?.requiresDarkGlass == true }), !packagingTokens.contains("dark_glass") {
            warnings.append(
                SolutionWarning(
                    code: "dark_glass_missing_when_required",
                    severity: .warning,
                    message: "По профилю стабильности требуется темное стекло",
                    state: .packagingAndStorageDone
                )
            )
            packagingTokens.append("dark_glass")
        }

        if items.contains(where: { $0.packaging?.requiresCoolStorage == true }), !storageTokens.contains("cool_storage") {
            warnings.append(
                SolutionWarning(
                    code: "cool_storage_missing_when_required",
                    severity: .warning,
                    message: "По профилю стабильности требуется хранение в прохладном месте",
                    state: .packagingAndStorageDone
                )
            )
            storageTokens.append("cool_storage")
        }

        if items.contains(where: { $0.packaging?.volatile == true }), !packagingTokens.contains("tight_closure") {
            warnings.append(
                SolutionWarning(
                    code: "tight_closure_missing_for_volatile_system",
                    severity: .warning,
                    message: "Для летучей системы требуется плотная укупорка",
                    state: .packagingAndStorageDone
                )
            )
            packagingTokens.append("tight_closure")
        }

        return (SolutionPackaging(packaging: packagingTokens, labels: labelTokens, storage: storageTokens), warnings)
    }

    private func mapPackagingToken(_ raw: String) -> [String] {
        let token = SolutionReferenceStore.normalizeToken(raw)
        if token.contains("dark") {
            if token.contains("tight") {
                return ["dark_glass", "tight_closure"]
            }
            return ["dark_glass"]
        }
        if token.contains("tight") {
            return ["tight_closure"]
        }
        if token.contains("bottle") || token.contains("glass") {
            return ["glass_bottle"]
        }
        return token.isEmpty ? [] : [token]
    }

    private func isControlledClassA(_ safety: SolutionSafetyRecord.Safety?) -> Bool {
        guard let safety else { return false }
        if safety.listA == true || safety.isListA_Poison == true {
            return true
        }
        return isControlledClassA(safety.controlledClass)
    }

    private func isControlledClassA(_ controlledClass: String?) -> Bool {
        guard let controlledClass else { return false }
        let token = SolutionReferenceStore.normalizeToken(controlledClass)
        return token == "a" || token == "list a" || token == "list_a" || token == "lista"
    }
}

struct PPKRenderer {
    func render(
        parsedInput: SolutionParsedInput,
        branch: SolutionBranchResolution,
        profile: SolutionClassificationProfile,
        route: SolutionRouteResolution,
        calculations: SolutionCalculationTrace,
        technologySteps: [String],
        warnings: [SolutionWarning],
        packaging: SolutionPackaging,
        references: SolutionReferenceStore
    ) -> (document: SolutionPPKDocument, warnings: [SolutionWarning]) {
        var sections: [String: [String]] = [:]
        var renderWarnings: [SolutionWarning] = []

        sections["input_data"] = [
            "Dosage form: \(parsedInput.dosageForm)",
            "Route: \(route.route)",
            "Branch: \(branch.branch)",
            "Profile.solutionType: \(profile.solutionType)",
            "Profile.solventType: \(profile.solventType)",
            "Profile.finalSystem: \(profile.finalSystem)",
            "Profile.solventCalculationMode: \(profile.solventCalculationMode)",
            "Profile.kouBand: \(profile.kouBand ?? "unknown")",
            "Profile.automaticRule: \(profile.automaticRule ?? "none")"
        ]

        sections["calculations"] = calculations.lines + [
            "sumSolidsG=\(format(calculations.sumSolidsG))",
            "sumCountedLiquidsMl=\(format(calculations.sumCountedLiquidsMl))",
            "waterToAddMl=\(format(calculations.waterToAddMl ?? 0))"
        ]

        sections["technology"] = technologySteps
        sections["validation"] = warnings.map { "\($0.code): \($0.message)" }
        sections["packaging"] = [
            "packaging=\(packaging.packaging.joined(separator: ","))",
            "labels=\(packaging.labels.joined(separator: ","))",
            "storage=\(packaging.storage.joined(separator: ","))"
        ]

        let requiredSectionKeys = references.ppkPhraseRules.sectionTemplates
            .filter { $0.required == true }
            .map(\.sectionKey)

        for requiredKey in requiredSectionKeys where sections[requiredKey] == nil {
            sections[requiredKey] = []
        }

        var ordered: [String] = []
        for template in references.ppkPhraseRules.sectionTemplates {
            if sections[template.sectionKey] != nil {
                ordered.append(template.sectionKey)
            }
        }

        for key in sections.keys where !ordered.contains(key) {
            ordered.append(key)
        }

        var renderedLines: [String] = []
        var seenSections: Set<String> = []

        for key in ordered {
            guard let lines = sections[key] else { continue }
            if seenSections.contains(key) {
                renderWarnings.append(
                    SolutionWarning(
                        code: "duplicate_section_render",
                        severity: .warning,
                        message: "Дублирующаяся секция \(key) удалена",
                        state: .ppcRendered
                    )
                )
                continue
            }
            seenSections.insert(key)

            renderedLines.append("[\(key)]")
            renderedLines.append(contentsOf: lines)
            renderedLines.append("")
        }

        let forbidden = references.ppkPhraseRules.forbiddenUniversalPhrases ?? []
        let sanitized = renderedLines.filter { line in
            !forbidden.contains(where: { forbiddenToken in
                let token = forbiddenToken.trimmingCharacters(in: .whitespacesAndNewlines)
                return !token.isEmpty && line.contains(token)
            })
        }

        if sanitized != renderedLines {
            renderWarnings.append(
                SolutionWarning(
                    code: "stock_qc_text_leak",
                    severity: .critical,
                    message: "Из финального ППК удалены запрещенные фразы контроля концентратов",
                    state: .ppcRendered
                )
            )
        }

        return (SolutionPPKDocument(sections: sections, renderedText: sanitized.joined(separator: "\n")), renderWarnings)
    }

    private func format(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
    }
}

private extension ModuleHelpers {
    static func uniqueOrderedWarnings(_ warnings: [SolutionWarning]) -> [SolutionWarning] {
        var seen: Set<String> = []
        var result: [SolutionWarning] = []
        for warning in warnings {
            let key = "\(warning.code)|\(warning.severity.rawValue)|\(warning.state?.rawValue ?? "")"
            if seen.insert(key).inserted {
                result.append(warning)
            }
        }
        return result
    }
}
