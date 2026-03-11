import Foundation

enum SolutionEngineState: String, CaseIterable, Codable {
    case inputReceived = "INPUT_RECEIVED"
    case inputParsed = "INPUT_PARSED"
    case ingredientsNormalized = "INGREDIENTS_NORMALIZED"
    case substancesResolved = "SUBSTANCES_RESOLVED"
    case behaviorProfilesAttached = "BEHAVIOR_PROFILES_ATTACHED"
    case routeResolved = "ROUTE_RESOLVED"
    case formClassified = "FORM_CLASSIFIED"
    case solutionBranchSelected = "SOLUTION_BRANCH_SELECTED"
    case preCalcChecksDone = "PRECALC_CHECKS_DONE"
    case coreCalculationsDone = "CORE_CALCULATIONS_DONE"
    case technologyPlanBuilt = "TECHNOLOGY_PLAN_BUILT"
    case validationDone = "VALIDATION_DONE"
    case doseControlDone = "DOSE_CONTROL_DONE"
    case packagingAndStorageDone = "PACKAGING_AND_STORAGE_DONE"
    case ppcRendered = "PPC_RENDERED"
    case finalResultEmitted = "FINAL_RESULT_EMITTED"
    case blocked = "BLOCKED"
    case partialWithWarnings = "PARTIAL_WITH_WARNINGS"
}

enum SolutionEngineConfidence: String, Codable {
    case exact
    case approximate
    case heuristic
    case blocked
}

enum SolutionWarningSeverity: String, Codable {
    case info
    case warning
    case critical
}

struct SolutionWarning: Hashable, Codable {
    let code: String
    let severity: SolutionWarningSeverity
    let message: String
    let state: SolutionEngineState?
}

struct SolutionCalculationTrace: Hashable, Codable {
    var targetVolumeMl: Double?
    var waterToAddMl: Double?
    var sumSolidsG: Double
    var sumCountedLiquidsMl: Double
    var kvoApplied: Bool
    var kvoContributionMl: Double
    var requiredMassesG: [String: Double]
    var concentrateVolumesMl: [String: Double]
    var lines: [String]

    init() {
        targetVolumeMl = nil
        waterToAddMl = nil
        sumSolidsG = 0
        sumCountedLiquidsMl = 0
        kvoApplied = false
        kvoContributionMl = 0
        requiredMassesG = [:]
        concentrateVolumesMl = [:]
        lines = []
    }
}

struct SolutionDoseControl: Hashable, Codable {
    var singleDoseMl: Double?
    var frequencyPerDay: Int?
    var dosesPerContainer: Double?
    var warnings: [String]

    init(singleDoseMl: Double? = nil, frequencyPerDay: Int? = nil, dosesPerContainer: Double? = nil, warnings: [String] = []) {
        self.singleDoseMl = singleDoseMl
        self.frequencyPerDay = frequencyPerDay
        self.dosesPerContainer = dosesPerContainer
        self.warnings = warnings
    }
}

struct SolutionPackaging: Hashable, Codable {
    var packaging: [String]
    var labels: [String]
    var storage: [String]

    init(packaging: [String] = [], labels: [String] = [], storage: [String] = []) {
        self.packaging = packaging
        self.labels = labels
        self.storage = storage
    }
}

struct SolutionPPKDocument: Hashable, Codable {
    var sections: [String: [String]]
    var renderedText: String

    init(sections: [String: [String]] = [:], renderedText: String = "") {
        self.sections = sections
        self.renderedText = renderedText
    }
}

struct SolutionClassificationProfile: Hashable, Codable {
    var dosageForm: String
    var solutionType: String
    var solventType: String
    var finalSystem: String
    var usesBurette: Bool
    var usesStandardSolution: Bool
    var usesConcentrate: Bool
    var needsHeating: Bool
    var needsFiltration: Bool
    var needsCoolingBeforeQs: Bool
    var needsVolumeCorrectionByKuo: Bool
    var needsNonAqueousRules: Bool
    var requiresSequenceControl: Bool
    var solventCalculationMode: String
    var kouValue: Double?
    var kouBand: String?
    var automaticRule: String?

    init(
        dosageForm: String = "solution",
        solutionType: String = "true_aqueous",
        solventType: String = "water",
        finalSystem: String = "true_solution",
        usesBurette: Bool = false,
        usesStandardSolution: Bool = false,
        usesConcentrate: Bool = false,
        needsHeating: Bool = false,
        needsFiltration: Bool = false,
        needsCoolingBeforeQs: Bool = false,
        needsVolumeCorrectionByKuo: Bool = false,
        needsNonAqueousRules: Bool = false,
        requiresSequenceControl: Bool = false,
        solventCalculationMode: String = "qs_to_volume",
        kouValue: Double? = nil,
        kouBand: String? = nil,
        automaticRule: String? = nil
    ) {
        self.dosageForm = dosageForm
        self.solutionType = solutionType
        self.solventType = solventType
        self.finalSystem = finalSystem
        self.usesBurette = usesBurette
        self.usesStandardSolution = usesStandardSolution
        self.usesConcentrate = usesConcentrate
        self.needsHeating = needsHeating
        self.needsFiltration = needsFiltration
        self.needsCoolingBeforeQs = needsCoolingBeforeQs
        self.needsVolumeCorrectionByKuo = needsVolumeCorrectionByKuo
        self.needsNonAqueousRules = needsNonAqueousRules
        self.requiresSequenceControl = requiresSequenceControl
        self.solventCalculationMode = solventCalculationMode
        self.kouValue = kouValue
        self.kouBand = kouBand
        self.automaticRule = automaticRule
    }
}

struct SolutionEngineResult: Hashable, Codable {
    var classification: String
    var solutionBranch: String?
    var route: String?
    var solutionProfile: SolutionClassificationProfile
    var normalizedIngredients: [SolutionNormalizedIngredient]
    var calculationTrace: SolutionCalculationTrace
    var technologySteps: [String]
    var technologyFlags: [String]
    var validationReport: [SolutionWarning]
    var doseControl: SolutionDoseControl
    var packaging: SolutionPackaging
    var warnings: [SolutionWarning]
    var ppkDocument: SolutionPPKDocument
    var confidence: SolutionEngineConfidence
    var debugTrace: [String]
    var state: SolutionEngineState
}

struct SolutionEngineRequest: Codable {
    var recipeText: String?
    var route: String?
    var structuredInput: StructuredSolutionInput?
    var forceReferenceConcentrate: [String: String]?

    init(recipeText: String? = nil, route: String? = nil, structuredInput: StructuredSolutionInput? = nil, forceReferenceConcentrate: [String: String]? = nil) {
        self.recipeText = recipeText
        self.route = route
        self.structuredInput = structuredInput
        self.forceReferenceConcentrate = forceReferenceConcentrate
    }
}

struct StructuredSolutionInput: Codable {
    var dosageForm: String?
    var route: String?
    var targetVolumeMl: Double?
    var signa: String?
    var ingredients: [StructuredIngredientInput]
}

struct StructuredIngredientInput: Codable {
    var name: String
    var presentationKind: String?
    var massG: Double?
    var volumeMl: Double?
    var concentrationPercent: Double?
    var ratio: String?
    var isAd: Bool?
    var adTargetMl: Double?
}

struct SolutionParsedInput {
    var dosageForm: String
    var routeHint: String?
    var signa: String
    var targetVolumeMl: Double?
    var ingredients: [SolutionParsedIngredient]
    var parserWarnings: [SolutionWarning]
}

struct SolutionParsedIngredient: Hashable {
    var id: UUID
    var rawLine: String
    var name: String
    var normalizedName: String
    var presentationKind: String?
    var massG: Double?
    var volumeMl: Double?
    var concentrationPercent: Double?
    var ratioDenominator: Double?
    var isAd: Bool
    var adTargetMl: Double?
    var isTargetSolutionLine: Bool
}

struct SolutionNormalizedIngredient: Hashable, Codable {
    var id: UUID
    var name: String
    var normalizedName: String
    var presentationKind: String?
    var massG: Double?
    var volumeMl: Double?
    var concentrationPercent: Double?
    var ratioDenominator: Double?
    var isAd: Bool
    var adTargetMl: Double?
    var isTargetSolutionLine: Bool
    var substanceKey: String?
    var behaviorType: String?
}

struct SolutionResolvedIngredient: Hashable {
    var base: SolutionNormalizedIngredient
    var substanceKey: String?
    var canonicalName: String?
    var safety: SolutionSafetyRecord?
    var doseLimit: SolutionDoseLimitRecord?
    var physchem: SolutionPhyschemRecord?
    var solutionReference: SolutionSolutionReferenceRecord?
}

struct SolutionBehaviorIngredient: Hashable {
    var resolved: SolutionResolvedIngredient
    var behavior: IngredientBehaviorRecord?
    var solubility: SolubilityRuleRecord?
    var specialCase: SpecialDissolutionCaseRecord?
    var concentrate: ConcentrateReferenceRecord?
    var packaging: StabilityPackagingRecord?
}

struct SolutionRouteResolution {
    var route: String
    var policy: RoutePolicyRecord?
    var usedFallback: Bool
}

struct SolutionBranchResolution {
    var classification: String
    var branch: String
}

struct SolutionEngineContext {
    var request: SolutionEngineRequest
    var parsedInput: SolutionParsedInput?
    var normalizedIngredients: [SolutionNormalizedIngredient]
    var resolvedIngredients: [SolutionResolvedIngredient]
    var behaviorIngredients: [SolutionBehaviorIngredient]
    var routeResolution: SolutionRouteResolution?
    var branchResolution: SolutionBranchResolution?
    var solutionProfile: SolutionClassificationProfile
    var calculations: SolutionCalculationTrace
    var technologySteps: [String]
    var technologyFlags: [String]
    var doseControl: SolutionDoseControl
    var packaging: SolutionPackaging
    var ppkDocument: SolutionPPKDocument
    var warnings: [SolutionWarning]
    var debugTrace: [String]
    var currentState: SolutionEngineState
    var blocked: Bool
    var fallbackTargetUsed: Bool
    var unresolvedRuleExists: Bool
    var missingBehaviorProfileExists: Bool
    var routeConflictExists: Bool

    init(request: SolutionEngineRequest) {
        self.request = request
        parsedInput = nil
        normalizedIngredients = []
        resolvedIngredients = []
        behaviorIngredients = []
        routeResolution = nil
        branchResolution = nil
        solutionProfile = SolutionClassificationProfile()
        calculations = SolutionCalculationTrace()
        technologySteps = []
        technologyFlags = []
        doseControl = SolutionDoseControl()
        packaging = SolutionPackaging()
        ppkDocument = SolutionPPKDocument()
        warnings = []
        debugTrace = []
        currentState = .inputReceived
        blocked = false
        fallbackTargetUsed = false
        unresolvedRuleExists = false
        missingBehaviorProfileExists = false
        routeConflictExists = false
    }

    mutating func appendWarning(_ warning: SolutionWarning) {
        if !warnings.contains(where: { $0.code == warning.code && $0.state == warning.state }) {
            warnings.append(warning)
        }
    }

    mutating func move(to newState: SolutionEngineState) {
        currentState = newState
        debugTrace.append(newState.rawValue)
    }
}

extension Double {
    func rounded3() -> Double {
        (self * 1000).rounded() / 1000
    }
}
