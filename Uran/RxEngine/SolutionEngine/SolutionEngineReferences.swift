import Foundation

private struct ItemsContainer<T: Decodable>: Decodable {
    let items: [T]
}

struct SubstanceAliasRecord: Decodable {
    struct Canonical: Decodable {
        let latNom: String?
        let latGen: String?
    }

    let substanceKey: String
    let canonical: Canonical?
    let aliases: [String]
}

struct SubstanceMasterRecord: Decodable {
    struct Name: Decodable {
        let latNom: String?
        let latGen: String?
    }

    struct Classification: Decodable {
        let typeRaw: String?
        let type: String?
        let byComposition: String?
        let pharmacologicalActivity: String?
        let byNature: String?
        let naturalGroup: String?
    }

    struct Technology: Decodable {
        let needsTrituration: Bool?
        let dissolutionType: String?
    }

    struct Safety: Decodable {
        let isNarcotic: Bool?
        let listA: Bool?
        let listB: Bool?
        let isListA_Poison: Bool?
    }

    let substanceKey: String
    let name: Name
    let classification: Classification?
    let technology: Technology?
    let safety: Safety?
}

struct SolutionPhyschemRecord: Decodable, Hashable {
    struct Physchem: Decodable, Hashable {
        let density: Double?
        let kuo: Double?
        let solubility: String?
        let storage: String?
        let interactionNotes: String?
    }

    let substanceKey: String
    let physchem: Physchem
}

struct SolutionSolutionReferenceRecord: Decodable, Hashable {
    struct SolutionRef: Decodable, Hashable {
        let solubility: String?
        let storage: String?
        let interactionNotes: String?
        let solventType: String?
        let sterile: Bool?
        let notesSolvent: String?
        let useRoutes: [String]?
        let process: String?
        let density: Double?
        let kuo: Double?
        let dissolutionType: String?
    }

    let substanceKey: String
    let solutions: SolutionRef
}

struct SolutionDoseLimitRecord: Decodable, Hashable {
    struct DoseLimits: Decodable, Hashable {
        let vrdG: Double?
        let vsdG: Double?
        let gttsPerMl: Double?
        let pedsVrdG: Double?
        let pedsRdG: Double?
        let vrdChild_0_1: Double?
        let vrdChild_1_6: Double?
        let vrdChild_7_14: Double?
    }

    let substanceKey: String
    let doseLimits: DoseLimits
}

struct SolutionSafetyRecord: Decodable, Hashable {
    struct Safety: Decodable, Hashable {
        let isNarcotic: Bool?
        let listA: Bool?
        let listB: Bool?
        let isListA_Poison: Bool?
        let controlledClass: String?
        let vrdG: Double?
        let vsdG: Double?
        let pedsVrdG: Double?
        let pedsRdG: Double?

        private enum CodingKeys: String, CodingKey {
            case isNarcotic
            case listA
            case listB
            case isListA_Poison
            case controlledClass
            case controlled_class
            case vrdG
            case vsdG
            case pedsVrdG
            case pedsRdG
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isNarcotic = try container.decodeIfPresent(Bool.self, forKey: .isNarcotic)
            listA = try container.decodeIfPresent(Bool.self, forKey: .listA)
            listB = try container.decodeIfPresent(Bool.self, forKey: .listB)
            isListA_Poison = try container.decodeIfPresent(Bool.self, forKey: .isListA_Poison)
            controlledClass = try container.decodeIfPresent(String.self, forKey: .controlledClass)
                ?? container.decodeIfPresent(String.self, forKey: .controlled_class)
            vrdG = try container.decodeIfPresent(Double.self, forKey: .vrdG)
            vsdG = try container.decodeIfPresent(Double.self, forKey: .vsdG)
            pedsVrdG = try container.decodeIfPresent(Double.self, forKey: .pedsVrdG)
            pedsRdG = try container.decodeIfPresent(Double.self, forKey: .pedsRdG)
        }
    }

    let substanceKey: String
    let safety: Safety
}

struct IngredientBehaviorRecord: Decodable, Hashable {
    let key: String
    let aliases: [String]
    let behaviorType: String
    let introductionMode: String
    let countsAsLiquid: Bool
    let countsAsSolid: Bool
    let affectsAd: Bool
    let affectsKvo: Bool
    let solubilityClass: String
    let phaseType: String
    let requiresSeparateDissolution: Bool
    let requiredPreDissolutionSolvent: String?
    let addAtEnd: Bool
    let orderPriority: Int
    let heatPolicy: String
    let volatilityPolicy: String
    let filtrationPolicy: String
    let lightSensitive: Bool
    let sterilitySensitive: Bool
    let routeRestrictions: [String]
    let compatibilityHints: [String]
}

struct SolubilityRuleRecord: Decodable, Hashable {
    let substanceKey: String
    let aliases: [String]
    let solubilityInWater: String
    let solubilityInAlcohol: String
    let solubilityInGlycerin: String
    let solubilityInOil: String
    let preferredSolvent: String
    let allowedSolutionBranches: [String]
    let requiresCoSolvent: Bool
    let requiresSeparateDissolution: Bool
    let recommendedPreDissolutionSolvent: String
    let heatingHelpful: Bool
    let heatingAllowed: Bool
    let solutionGate: String
    let notes: [String]
}

struct ConcentrateReferenceRecord: Decodable, Hashable {
    let substanceKey: String
    let aliases: [String]
    let hasStandardConcentrate: Bool
    let concentrateName: String?
    let concentrationPercent: Double?
    let concentrationDecimalGPerMl: Double?
    let ratioNotation: String?
    let calculationMode: String
    let formula: String?
    let formulaAlt: String?
    let presentationKind: String?
    let phaseType: String?
    let isBuretteCompatible: Bool
    let defaultUsePath: String
    let notes: [String]
}

struct SpecialDissolutionCaseRecord: Decodable, Hashable {
    let caseKey: String
    let aliases: [String]
    let caseType: String
    let defaultRouteScope: [String]
    let allowedBranches: [String]
    let requiresSeparateDissolution: Bool
    let preDissolutionStageRequired: Bool
    let recommendedPrimarySolvent: String
    let recommendedPreDissolutionSolvent: String
    let dissolutionMethod: String
    let heatingPolicy: String
    let filtrationPolicy: String
    let orderPolicy: String
    let countsAsSolidInitially: Bool
    let countsAsLiquidAfterDissolution: Bool
    let blocksSimpleAutoPath: Bool
    let specialWarnings: [String]
    let technologyTemplate: [String]
    let notes: [String]
}

struct RoutePolicyRecord: Decodable, Hashable {
    struct TechnologyPolicy: Decodable, Hashable {
        let allowHeatingIfIngredientAllows: Bool
        let allowRoutineFiltrationIfIndicated: Bool
        let allowDarkGlassIfComponentRequires: Bool
        let allowCoolStorageIfComponentRequires: Bool
        let defaultShakeLabel: Bool
    }

    let routeKey: String
    let aliases: [String]
    let routeType: String
    let allowedSolutionBranches: [String]
    let defaultPackaging: String
    let defaultLabels: [String]
    let additionalLabels: [String]
    let requiresSterility: Bool
    let requiresIsotonicityCheck: Bool
    let requiresPHCheck: Bool
    let requiresDoseControlWhenApplicable: Bool
    let defaultDoseParserEnabled: Bool
    let supportsSpoonDosing: Bool
    let supportsMlDosing: Bool
    let supportsDropDosing: Bool
    let defaultQualityControl: [String]
    let forbiddenByDefault: [String]
    let technologyPolicy: TechnologyPolicy
    let notes: [String]
}

struct StabilityPackagingRecord: Decodable, Hashable {
    let substanceKey: String
    let aliases: [String]
    let controlledClass: String?
    let container: String?
    let lightSensitive: Bool
    let volatile: Bool
    let requiresDarkGlass: Bool
    let requiresCoolStorage: Bool
    let requiresShakeLabel: Bool
    let requiresNoHeating: Bool
    let prefersAddAtEnd: Bool
    let filtrationCaution: Bool
    let defaultPackaging: String
    let defaultLabels: [String]
    let storageLabels: [String]
    let technologyWarnings: [String]
    let notes: [String]

    private enum CodingKeys: String, CodingKey {
        case substanceKey
        case aliases
        case controlledClass
        case controlled_class
        case container
        case lightSensitive
        case light_sensitive
        case volatile
        case requiresDarkGlass
        case requiresCoolStorage
        case requiresShakeLabel
        case requiresNoHeating
        case prefersAddAtEnd
        case filtrationCaution
        case defaultPackaging
        case defaultLabels
        case storageLabels
        case technologyWarnings
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        substanceKey = try container.decode(String.self, forKey: .substanceKey)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        controlledClass = try container.decodeIfPresent(String.self, forKey: .controlledClass)
            ?? container.decodeIfPresent(String.self, forKey: .controlled_class)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        lightSensitive = try container.decodeIfPresent(Bool.self, forKey: .lightSensitive)
            ?? container.decodeIfPresent(Bool.self, forKey: .light_sensitive)
            ?? false
        volatile = try container.decodeIfPresent(Bool.self, forKey: .volatile) ?? false
        requiresDarkGlass = try container.decodeIfPresent(Bool.self, forKey: .requiresDarkGlass) ?? false
        requiresCoolStorage = try container.decodeIfPresent(Bool.self, forKey: .requiresCoolStorage) ?? false
        requiresShakeLabel = try container.decodeIfPresent(Bool.self, forKey: .requiresShakeLabel) ?? false
        requiresNoHeating = try container.decodeIfPresent(Bool.self, forKey: .requiresNoHeating) ?? false
        prefersAddAtEnd = try container.decodeIfPresent(Bool.self, forKey: .prefersAddAtEnd) ?? false
        filtrationCaution = try container.decodeIfPresent(Bool.self, forKey: .filtrationCaution) ?? false
        defaultPackaging = try container.decodeIfPresent(String.self, forKey: .defaultPackaging) ?? ""
        defaultLabels = try container.decodeIfPresent([String].self, forKey: .defaultLabels) ?? []
        storageLabels = try container.decodeIfPresent([String].self, forKey: .storageLabels) ?? []
        technologyWarnings = try container.decodeIfPresent([String].self, forKey: .technologyWarnings) ?? []
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

struct ValidationConflictRuleRecord: Decodable, Hashable {
    let ruleKey: String
    let category: String
    let severity: String
    let condition: String
    let message: String
    let engineAction: String
    let notes: [String]
}

private struct ValidationConflictRoot: Decodable {
    let rules: [ValidationConflictRuleRecord]
}

struct PPKPhraseSectionTemplate: Decodable {
    let sectionKey: String
    let required: Bool?
}

struct PPKPhraseGlobalRule: Decodable {
    let ruleKey: String
    let appliesTo: [String]?
    let condition: String?
    let action: String?
    let severity: String?
}

struct PPKPhraseRulesRoot: Decodable {
    let sectionTemplates: [PPKPhraseSectionTemplate]
    let globalRules: [PPKPhraseGlobalRule]
    let forbiddenUniversalPhrases: [String]?
}

struct RegexNormalizationPattern: Decodable {
    let patternKey: String
    let stage: String
    let pattern: String
    let replacement: String
    let flags: String
}

private struct RegexNormalizationRoot: Decodable {
    let patterns: [RegexNormalizationPattern]
}

struct NormalizationDictionaryRoot: Decodable {
    let routeHints: [String: [String]]
    let spoonDoseVocabulary: [String: [String]]
    let spoonConversionsMl: [String: Double]
    let frequencyVocabulary: [String: [String]]
}

struct ManualOverrideAction: Decodable {
    let forceBranch: String?
    let blockBranches: [String]?
    let forceConfidence: String?
    let addWarnings: [String]?
}

struct ManualOverrideMatch: Decodable {
    let substanceKeys: [String]?
    let route: String?
}

struct ManualOverrideItem: Decodable {
    let overrideKey: String
    let overrideType: String
    let enabled: Bool
    let match: ManualOverrideMatch
    let action: ManualOverrideAction
    let reason: String
}

private struct ManualOverrideRoot: Decodable {
    let items: [ManualOverrideItem]
}

final class SolutionReferenceStore {
    let baseURL: URL

    let normalizationDictionary: NormalizationDictionaryRoot
    let regexPatterns: [RegexNormalizationPattern]

    let substanceAliases: [SubstanceAliasRecord]
    let solutionSpecAliases: [SubstanceAliasRecord]
    let substancesMaster: [SubstanceMasterRecord]
    let physchem: [SolutionPhyschemRecord]
    let solutionReference: [SolutionSolutionReferenceRecord]
    let doseLimits: [SolutionDoseLimitRecord]
    let safetyReference: [SolutionSafetyRecord]

    let ingredientBehaviors: [IngredientBehaviorRecord]
    let solubilityRules: [SolubilityRuleRecord]
    let concentrateReference: [ConcentrateReferenceRecord]
    let specialDissolutionCases: [SpecialDissolutionCaseRecord]
    let routePolicies: [RoutePolicyRecord]
    let stabilityAndPackaging: [StabilityPackagingRecord]
    let validationRules: [ValidationConflictRuleRecord]
    let ppkPhraseRules: PPKPhraseRulesRoot
    let manualOverrides: [ManualOverrideItem]

    let aliasToSubstanceKey: [String: String]
    let substanceMasterByKey: [String: SubstanceMasterRecord]
    let physchemByKey: [String: SolutionPhyschemRecord]
    let solutionReferenceByKey: [String: SolutionSolutionReferenceRecord]
    let doseLimitsByKey: [String: SolutionDoseLimitRecord]
    let safetyByKey: [String: SolutionSafetyRecord]
    let behaviorByAlias: [String: IngredientBehaviorRecord]
    let solubilityByAlias: [String: SolubilityRuleRecord]
    let concentrateByAlias: [String: ConcentrateReferenceRecord]
    let specialCaseByAlias: [String: SpecialDissolutionCaseRecord]
    let packagingByAlias: [String: StabilityPackagingRecord]
    let routeByAlias: [String: RoutePolicyRecord]
    let routeByKey: [String: RoutePolicyRecord]
    let validationByRuleKey: [String: ValidationConflictRuleRecord]
    let specAliasToSpecKey: [String: String]
    let specCanonicalNomBySpecKey: [String: String]

    init(baseURL: URL? = nil) throws {
        self.baseURL = try Self.resolveBaseURL(provided: baseURL)
        let resolvedFrom = baseURL == nil ? "auto" : "provided"
        Self.debugLog("resolved baseURL [\(resolvedFrom)] = \(self.baseURL.standardizedFileURL.path)")

        normalizationDictionary = try Self.decodeFile(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/normalization/NORMALIZATION_DICTIONARY.json"))
        let regexRoot: RegexNormalizationRoot = try Self.decodeFile(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/normalization/REGEX_NORMALIZATION_PATTERNS.json"))
        regexPatterns = regexRoot.patterns

        substanceAliases = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/substance_alias_table.json"))
        // Use a unique filename to avoid flat-bundle case-insensitive collisions
        // with `reference/parsed/substance_alias_table.json`.
        solutionSpecAliases = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/SUBSTANCE_ALIAS_TABLE_SOLUTIONS.json"))
        substancesMaster = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/substances_master.json"))
        physchem = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/physchem_reference.json"))
        solutionReference = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/solution_reference.json"))
        doseLimits = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/dose_limits.json"))
        safetyReference = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "reference/parsed/safety_reference.json"))

        ingredientBehaviors = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/INGREDIENT_BEHAVIOR_TABLE_SOLUTIONS.json"))
        solubilityRules = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/SOLUBILITY_RULES_TABLE.json"))
        concentrateReference = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/CONCENTRATE_REFERENCE_TABLE.json"))
        specialDissolutionCases = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/SPECIAL_DISSOLUTION_CASES_SOLUTIONS.json"))
        routePolicies = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/ROUTE_POLICY_TABLE_SOLUTIONS.json"))
        stabilityAndPackaging = try Self.decodeItems(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/STABILITY_AND_PACKAGING_TABLE_SOLUTIONS.json"))
        let validationRoot: ValidationConflictRoot = try Self.decodeFile(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/VALIDATION_CONFLICT_RULES_SOLUTIONS.json"))
        validationRules = validationRoot.rules
        ppkPhraseRules = try Self.decodeFile(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "solutions_spec/PPC_PHRASE_RULES_SOLUTIONS.json"))
        let overrideRoot: ManualOverrideRoot = try Self.decodeFile(at: Self.resourceURL(baseURL: self.baseURL, relativePath: "engine_support/MANUAL_OVERRIDE_LAYER.json"))
        manualOverrides = overrideRoot.items.filter { $0.enabled }

        var aliasMap: [String: String] = [:]
        for alias in substanceAliases {
            aliasMap[Self.normalizeToken(alias.substanceKey)] = alias.substanceKey
            for value in alias.aliases {
                aliasMap[Self.normalizeToken(value)] = alias.substanceKey
            }
            if let nom = alias.canonical?.latNom {
                aliasMap[Self.normalizeToken(nom)] = alias.substanceKey
            }
            if let gen = alias.canonical?.latGen {
                aliasMap[Self.normalizeToken(gen)] = alias.substanceKey
            }
        }
        // Bridge gaps in parsed alias table with solutions-spec aliases (e.g. Iodum).
        // Keep parsed mappings as first priority and only fill missing tokens.
        for alias in solutionSpecAliases {
            let key = alias.substanceKey
            let candidates = [key, key.replacingOccurrences(of: "_", with: " ")]
                + alias.aliases
                + [alias.canonical?.latNom, alias.canonical?.latGen].compactMap { $0 }
            for candidate in candidates {
                let token = Self.normalizeToken(candidate)
                if aliasMap[token] == nil {
                    aliasMap[token] = key
                }
            }
        }
        aliasToSubstanceKey = aliasMap

        var specAliasMap: [String: String] = [:]
        var specCanonicalMap: [String: String] = [:]
        for alias in solutionSpecAliases {
            let specKey = alias.substanceKey
            let normalizedSpecKey = Self.normalizeToken(specKey)
            specAliasMap[normalizedSpecKey] = specKey
            specAliasMap[Self.normalizeToken(specKey.replacingOccurrences(of: "_", with: " "))] = specKey
            for value in alias.aliases {
                specAliasMap[Self.normalizeToken(value)] = specKey
            }
            if let nom = alias.canonical?.latNom {
                specCanonicalMap[specKey] = nom
                specAliasMap[Self.normalizeToken(nom)] = specKey
            }
            if let gen = alias.canonical?.latGen {
                specAliasMap[Self.normalizeToken(gen)] = specKey
            }
        }
        specAliasToSpecKey = specAliasMap
        specCanonicalNomBySpecKey = specCanonicalMap

        substanceMasterByKey = Self.buildFirstWinsMap(records: substancesMaster) { Self.normalizeToken($0.substanceKey) }
        physchemByKey = Self.buildFirstWinsMap(records: physchem) { Self.normalizeToken($0.substanceKey) }
        solutionReferenceByKey = Self.buildFirstWinsMap(records: solutionReference) { Self.normalizeToken($0.substanceKey) }
        doseLimitsByKey = Self.buildFirstWinsMap(records: doseLimits) { Self.normalizeToken($0.substanceKey) }
        safetyByKey = Self.buildFirstWinsMap(records: safetyReference) { Self.normalizeToken($0.substanceKey) }

        behaviorByAlias = Self.buildAliasMap(records: ingredientBehaviors) { item in
            [item.key] + item.aliases
        }
        solubilityByAlias = Self.buildAliasMap(records: solubilityRules) { item in
            [item.substanceKey] + item.aliases
        }
        concentrateByAlias = Self.buildAliasMap(records: concentrateReference) { item in
            [item.substanceKey] + item.aliases
        }
        specialCaseByAlias = Self.buildAliasMap(records: specialDissolutionCases) { item in
            [item.caseKey] + item.aliases
        }
        packagingByAlias = Self.buildAliasMap(records: stabilityAndPackaging) { item in
            [item.substanceKey] + item.aliases
        }
        routeByAlias = Self.buildAliasMap(records: routePolicies) { item in
            [item.routeKey] + item.aliases
        }
        routeByKey = Self.buildFirstWinsMap(records: routePolicies) { Self.normalizeToken($0.routeKey) }
        validationByRuleKey = Self.buildFirstWinsMap(records: validationRules) { $0.ruleKey }
    }

    func resolveSubstanceKey(for name: String) -> String? {
        let token = Self.normalizeToken(name)
        return aliasToSubstanceKey[token]
    }

    func resolveBehavior(for normalizedName: String, substanceKey: String?) -> IngredientBehaviorRecord? {
        for token in candidateTokens(normalizedName: normalizedName, substanceKey: substanceKey) {
            if let value = behaviorByAlias[token] {
                return value
            }
        }
        return nil
    }

    func resolveSolubility(for normalizedName: String, substanceKey: String?) -> SolubilityRuleRecord? {
        for token in candidateTokens(normalizedName: normalizedName, substanceKey: substanceKey) {
            if let value = solubilityByAlias[token] {
                return value
            }
        }
        return nil
    }

    func resolveConcentrate(for normalizedName: String, substanceKey: String?) -> ConcentrateReferenceRecord? {
        for token in candidateTokens(normalizedName: normalizedName, substanceKey: substanceKey) {
            if let value = concentrateByAlias[token] {
                return value
            }
        }
        return nil
    }

    func resolveSpecialCase(for normalizedName: String, substanceKey: String?) -> SpecialDissolutionCaseRecord? {
        for token in candidateTokens(normalizedName: normalizedName, substanceKey: substanceKey) {
            if let value = specialCaseByAlias[token] {
                return value
            }
        }
        return nil
    }

    func resolvePackaging(for normalizedName: String, substanceKey: String?) -> StabilityPackagingRecord? {
        for token in candidateTokens(normalizedName: normalizedName, substanceKey: substanceKey) {
            if let value = packagingByAlias[token] {
                return value
            }
        }
        return nil
    }

    func resolveSpecSubstanceKey(for normalizedName: String, substanceKey: String?) -> String? {
        if let substanceKey {
            let keyToken = Self.normalizeToken(substanceKey)
            if let match = specAliasToSpecKey[keyToken] {
                return match
            }
            let spaced = Self.normalizeToken(substanceKey.replacingOccurrences(of: "_", with: " "))
            if let match = specAliasToSpecKey[spaced] {
                return match
            }
        }
        return specAliasToSpecKey[Self.normalizeToken(normalizedName)]
    }

    func resolveSpecCanonicalName(for normalizedName: String, substanceKey: String?) -> String? {
        guard let specKey = resolveSpecSubstanceKey(for: normalizedName, substanceKey: substanceKey) else {
            return nil
        }
        return specCanonicalNomBySpecKey[specKey]
    }

    func resolveRoutePolicy(for routeCandidate: String) -> RoutePolicyRecord? {
        routeByAlias[Self.normalizeToken(routeCandidate)]
    }

    nonisolated static func normalizeToken(_ token: String) -> String {
        let lowered = token
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        let compact = String(allowed)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact
    }

    private static func resolveBaseURL(provided: URL?) throws -> URL {
        if let provided {
            let resolved = provided.standardizedFileURL
            debugLog("resolveBaseURL using provided path = \(resolved.path)")
            return resolved
        }

        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("URAN_Pharma_Engine"))
            candidates.append(resourceURL.appendingPathComponent("Uran/URAN_Pharma_Engine"))
            candidates.append(resourceURL)
        }
        candidates.append(cwd.appendingPathComponent("Uran/URAN_Pharma_Engine"))
        candidates.append(cwd.appendingPathComponent("URAN_Pharma_Engine"))
        candidates.append(URL(fileURLWithPath: "/Users/eugentamara/URAN/Uran/URAN_Pharma_Engine"))

        for candidate in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                let resolved = candidate.standardizedFileURL
                debugLog("resolveBaseURL selected candidate = \(resolved.path)")
                return resolved
            }
        }

        let candidatePaths = candidates.map { $0.standardizedFileURL.path }.joined(separator: " | ")
        debugLog("resolveBaseURL failed; cwd=\(cwd.standardizedFileURL.path); candidates=\(candidatePaths)")
        throw NSError(domain: "SolutionReferenceStore", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "URAN_Pharma_Engine folder not found"
        ])
    }

    private static func debugLog(_ message: String) {
#if DEBUG
        print("[SolutionReferenceStore] \(message)")
#endif
    }

    private static func resourceURL(baseURL: URL, relativePath: String) throws -> URL {
        let fm = FileManager.default
        let nested = baseURL.appendingPathComponent(relativePath)
        if fm.isReadableFile(atPath: nested.path) {
            return nested
        }

        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let flat = baseURL.appendingPathComponent(fileName)
        if fm.isReadableFile(atPath: flat.path) {
            Self.debugLog("resource fallback (flat) \(relativePath) -> \(flat.standardizedFileURL.path)")
            return flat
        }

        if let caseInsensitive = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil).first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame
        }), fm.isReadableFile(atPath: caseInsensitive.path) {
            Self.debugLog("resource fallback (case-insensitive) \(relativePath) -> \(caseInsensitive.standardizedFileURL.path)")
            return caseInsensitive
        }

        throw NSError(domain: "SolutionReferenceStore", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Reference file not found: \(relativePath)",
            "baseURL": baseURL.path
        ])
    }

    private static func decodeItems<T: Decodable>(at url: URL) throws -> [T] {
        let root: ItemsContainer<T> = try decodeFile(at: url)
        return root.items
    }

    private static func decodeFile<T: Decodable>(at url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private static func buildAliasMap<T>(records: [T], aliases: (T) -> [String]) -> [String: T] {
        var map: [String: T] = [:]
        for record in records {
            for alias in aliases(record) {
                map[normalizeToken(alias)] = record
            }
        }
        return map
    }

    private static func buildFirstWinsMap<T>(records: [T], key: (T) -> String) -> [String: T] {
        var map: [String: T] = [:]
        for record in records {
            let recordKey = key(record)
            if map[recordKey] == nil {
                map[recordKey] = record
            }
        }
        return map
    }

    private func candidateTokens(normalizedName: String, substanceKey: String?) -> [String] {
        var tokens: [String] = []
        if let substanceKey {
            tokens.append(Self.normalizeToken(substanceKey))
            tokens.append(Self.normalizeToken(substanceKey.replacingOccurrences(of: "_", with: " ")))
        }
        if let specKey = resolveSpecSubstanceKey(for: normalizedName, substanceKey: substanceKey) {
            tokens.append(Self.normalizeToken(specKey))
            tokens.append(Self.normalizeToken(specKey.replacingOccurrences(of: "_", with: " ")))
            if let canonical = specCanonicalNomBySpecKey[specKey] {
                tokens.append(Self.normalizeToken(canonical))
            }
        }
        tokens.append(Self.normalizeToken(normalizedName))
        return Array(Set(tokens))
    }
}
