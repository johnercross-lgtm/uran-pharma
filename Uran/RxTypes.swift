import Foundation

struct UnitCode: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

enum IngredientRole: String, Codable, CaseIterable, Sendable {
    case active
    case base
    case solvent
    case excipient
    case other
}

enum AmountScope: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case auto
    case total
    case perDose

    var id: String { rawValue }
}

enum RxIssueSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case blocking
}

struct RxIssue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var code: String
    var severity: RxIssueSeverity
    var message: String

    init(id: UUID = UUID(), code: String, severity: RxIssueSeverity, message: String) {
        self.id = id
        self.code = code
        self.severity = severity
        self.message = message
    }
}

enum TechStepKind: String, Codable, CaseIterable, Sendable {
    case prep
    case trituration
    case dissolution
    case mixing
    case bringToVolume
    case filtration
    case sterilization
    case packaging
    case labeling
}

struct TechStep: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var kind: TechStepKind
    var title: String
    var notes: String?
    var ingredientIds: [UUID] = []
    var isCritical: Bool = false

    init(
        id: UUID = UUID(),
        kind: TechStepKind,
        title: String,
        notes: String? = nil,
        ingredientIds: [UUID] = [],
        isCritical: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.notes = notes
        self.ingredientIds = ingredientIds
        self.isCritical = isCritical
    }
}

struct TechPlan: Hashable, Codable, Sendable {
    var steps: [TechStep] = []
}

struct PpkSection: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String
    var lines: [String]

    init(id: UUID = UUID(), title: String, lines: [String]) {
        self.id = id
        self.title = title
        self.lines = lines
    }
}

enum TechnologySource: String, Codable, CaseIterable, Sendable {
    case ingredient
    case burette
    case inferredWater
    case inferredOperation
}

enum TechnologyStage: String, Codable, CaseIterable, Sendable {
    case concentrates
    case additives
    case solvent
    case finalAdjustment
    case other
}

struct TechnologyOrderItem: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var stepIndex: Int
    var ingredientId: UUID?
    var ingredientName: String
    var amountText: String
    var unitText: String
    var note: String?
    var volumeMl: Double?
    var massG: Double?
    var source: TechnologySource
    var stage: TechnologyStage

    init(
        id: UUID = UUID(),
        stepIndex: Int,
        ingredientId: UUID?,
        ingredientName: String,
        amountText: String,
        unitText: String,
        note: String? = nil,
        volumeMl: Double? = nil,
        massG: Double? = nil,
        source: TechnologySource = .ingredient,
        stage: TechnologyStage = .other
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.ingredientId = ingredientId
        self.ingredientName = ingredientName
        self.amountText = amountText
        self.unitText = unitText
        self.note = note
        self.volumeMl = volumeMl
        self.massG = massG
        self.source = source
        self.stage = stage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stepIndex
        case ingredientId
        case ingredientName
        case amountText
        case unitText
        case note
        case volumeMl
        case massG
        case source
        case stage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        stepIndex = try container.decode(Int.self, forKey: .stepIndex)
        ingredientId = try container.decodeIfPresent(UUID.self, forKey: .ingredientId)
        ingredientName = try container.decode(String.self, forKey: .ingredientName)
        amountText = try container.decode(String.self, forKey: .amountText)
        unitText = try container.decode(String.self, forKey: .unitText)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        volumeMl = try container.decodeIfPresent(Double.self, forKey: .volumeMl)
        massG = try container.decodeIfPresent(Double.self, forKey: .massG)
        source = try container.decodeIfPresent(TechnologySource.self, forKey: .source) ?? .ingredient
        stage = try container.decodeIfPresent(TechnologyStage.self, forKey: .stage) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stepIndex, forKey: .stepIndex)
        try container.encodeIfPresent(ingredientId, forKey: .ingredientId)
        try container.encode(ingredientName, forKey: .ingredientName)
        try container.encode(amountText, forKey: .amountText)
        try container.encode(unitText, forKey: .unitText)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(volumeMl, forKey: .volumeMl)
        try container.encodeIfPresent(massG, forKey: .massG)
        try container.encode(source, forKey: .source)
        try container.encode(stage, forKey: .stage)
    }
}

struct PpkDocument: Hashable, Codable, Sendable {
    var backSide: [PpkSection] = []
    var faceSide: [PpkSection] = []
    var control: [PpkSection] = []
    var technologyOrder: [TechnologyOrderItem] = []
}

struct RxIngredientLine: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var amount: Double
    var unit: UnitCode
    var flags: [String]

    init(id: UUID = UUID(), name: String, amount: Double, unit: UnitCode, flags: [String] = []) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.flags = flags
    }
}

struct RxRenderModel: Hashable, Codable, Sendable {
    var ingredients: [RxIngredientLine] = []
    var mfCommand: String?
    var dtdCommand: String?
    var signa: String?
}

struct SolutionEngineLegacySnapshot: Hashable, Codable, Sendable {
    var routeBranch: String?
    var activatedBlocks: [String]
    var blockingIssueCodes: [String]
    var warningIssueCodes: [String]
    var allIssueCodes: [String]
    var confidence: String
    var calculationKeys: [String]
    var waterToAddMl: Double?
    var techStepKinds: [String]
    var technologySteps: [String]
    var packaging: [String]
    var labels: [String]

    init(
        routeBranch: String? = nil,
        activatedBlocks: [String] = [],
        blockingIssueCodes: [String] = [],
        warningIssueCodes: [String] = [],
        allIssueCodes: [String] = [],
        confidence: String = "approximate",
        calculationKeys: [String] = [],
        waterToAddMl: Double? = nil,
        techStepKinds: [String] = [],
        technologySteps: [String] = [],
        packaging: [String] = [],
        labels: [String] = []
    ) {
        self.routeBranch = routeBranch
        self.activatedBlocks = activatedBlocks
        self.blockingIssueCodes = blockingIssueCodes
        self.warningIssueCodes = warningIssueCodes
        self.allIssueCodes = allIssueCodes
        self.confidence = confidence
        self.calculationKeys = calculationKeys
        self.waterToAddMl = waterToAddMl
        self.techStepKinds = techStepKinds
        self.technologySteps = technologySteps
        self.packaging = packaging
        self.labels = labels
    }
}

struct SolutionEngineV1Snapshot: Hashable, Codable, Sendable {
    var route: String?
    var branch: String?
    var confidence: String
    var state: String
    var warningCodes: [String]
    var criticalWarningCodes: [String]
    var technologyFlags: [String]
    var technologySteps: [String]
    var packaging: [String]
    var labels: [String]
    var storage: [String]
    var waterToAddMl: Double?

    init(
        route: String? = nil,
        branch: String? = nil,
        confidence: String = "heuristic",
        state: String = "PARTIAL_WITH_WARNINGS",
        warningCodes: [String] = [],
        criticalWarningCodes: [String] = [],
        technologyFlags: [String] = [],
        technologySteps: [String] = [],
        packaging: [String] = [],
        labels: [String] = [],
        storage: [String] = [],
        waterToAddMl: Double? = nil
    ) {
        self.route = route
        self.branch = branch
        self.confidence = confidence
        self.state = state
        self.warningCodes = warningCodes
        self.criticalWarningCodes = criticalWarningCodes
        self.technologyFlags = technologyFlags
        self.technologySteps = technologySteps
        self.packaging = packaging
        self.labels = labels
        self.storage = storage
        self.waterToAddMl = waterToAddMl
    }
}

enum SolutionShadowMismatchSeverity: String, Codable, Sendable {
    case none
    case nonCritical = "non_critical"
    case critical
}

struct SolutionLegacyReasoningSnapshot: Hashable, Codable, Sendable {
    var form: String?
    var route: String?
    var branch: String?
    var roles: [String: String]
    var solidsPercent: Double?
    var useKUO: Bool?
    var adjustToFinalVolumeLast: Bool?
    var warnings: [String]
    var decisionTrace: [String]

    init(
        form: String? = nil,
        route: String? = nil,
        branch: String? = nil,
        roles: [String: String] = [:],
        solidsPercent: Double? = nil,
        useKUO: Bool? = nil,
        adjustToFinalVolumeLast: Bool? = nil,
        warnings: [String] = [],
        decisionTrace: [String] = []
    ) {
        self.form = form
        self.route = route
        self.branch = branch
        self.roles = roles
        self.solidsPercent = solidsPercent
        self.useKUO = useKUO
        self.adjustToFinalVolumeLast = adjustToFinalVolumeLast
        self.warnings = warnings
        self.decisionTrace = decisionTrace
    }
}

struct SolutionReasoningSnapshot: Hashable, Codable, Sendable {
    var form: String?
    var route: String?
    var branch: String?
    var roles: [String: String]
    var solidsPercent: Double?
    var useKUO: Bool?
    var adjustToFinalVolumeLast: Bool?
    var warnings: [String]
    var decisionTrace: [String]

    init(
        form: String? = nil,
        route: String? = nil,
        branch: String? = nil,
        roles: [String: String] = [:],
        solidsPercent: Double? = nil,
        useKUO: Bool? = nil,
        adjustToFinalVolumeLast: Bool? = nil,
        warnings: [String] = [],
        decisionTrace: [String] = []
    ) {
        self.form = form
        self.route = route
        self.branch = branch
        self.roles = roles
        self.solidsPercent = solidsPercent
        self.useKUO = useKUO
        self.adjustToFinalVolumeLast = adjustToFinalVolumeLast
        self.warnings = warnings
        self.decisionTrace = decisionTrace
    }
}

struct SolutionReasoningShadowReport: Hashable, Codable, Sendable {
    var enabled: Bool
    var compared: Bool
    var hasMismatch: Bool
    var mismatchReasons: [String]
    var formDiffers: Bool
    var routeDiffers: Bool
    var branchDiffers: Bool
    var rolesDiffers: Bool
    var solidsPercentDiffers: Bool
    var kuoDiffers: Bool
    var volumeStrategyDiffers: Bool
    var warningsDiffers: Bool
    var decisionTraceDiffers: Bool
    var legacy: SolutionLegacyReasoningSnapshot?
    var reasoning: SolutionReasoningSnapshot?
    var debugLines: [String]

    init(
        enabled: Bool = false,
        compared: Bool = false,
        hasMismatch: Bool = false,
        mismatchReasons: [String] = [],
        formDiffers: Bool = false,
        routeDiffers: Bool = false,
        branchDiffers: Bool = false,
        rolesDiffers: Bool = false,
        solidsPercentDiffers: Bool = false,
        kuoDiffers: Bool = false,
        volumeStrategyDiffers: Bool = false,
        warningsDiffers: Bool = false,
        decisionTraceDiffers: Bool = false,
        legacy: SolutionLegacyReasoningSnapshot? = nil,
        reasoning: SolutionReasoningSnapshot? = nil,
        debugLines: [String] = []
    ) {
        self.enabled = enabled
        self.compared = compared
        self.hasMismatch = hasMismatch
        self.mismatchReasons = mismatchReasons
        self.formDiffers = formDiffers
        self.routeDiffers = routeDiffers
        self.branchDiffers = branchDiffers
        self.rolesDiffers = rolesDiffers
        self.solidsPercentDiffers = solidsPercentDiffers
        self.kuoDiffers = kuoDiffers
        self.volumeStrategyDiffers = volumeStrategyDiffers
        self.warningsDiffers = warningsDiffers
        self.decisionTraceDiffers = decisionTraceDiffers
        self.legacy = legacy
        self.reasoning = reasoning
        self.debugLines = debugLines
    }
}

struct SolutionEngineShadowReport: Hashable, Codable, Sendable {
    var enabled: Bool
    var compared: Bool
    var hasMismatch: Bool
    var mismatchReasons: [String]
    var mismatchSeverity: SolutionShadowMismatchSeverity
    var warningsDiffers: Bool
    var waterToAddDiffers: Bool
    var technologyStepsDiffers: Bool
    var packagingDiffers: Bool
    var labelsDiffers: Bool
    var confidenceDiffers: Bool
    var whitelistEligible: Bool
    var preferV1Enabled: Bool
    var v1SelectedAsPrimary: Bool
    var fallbackUsed: Bool
    var legacy: SolutionEngineLegacySnapshot?
    var solutionV1: SolutionEngineV1Snapshot?
    var reasoningShadow: SolutionReasoningShadowReport?
    var debugLines: [String]

    init(
        enabled: Bool = false,
        compared: Bool = false,
        hasMismatch: Bool = false,
        mismatchReasons: [String] = [],
        mismatchSeverity: SolutionShadowMismatchSeverity = .none,
        warningsDiffers: Bool = false,
        waterToAddDiffers: Bool = false,
        technologyStepsDiffers: Bool = false,
        packagingDiffers: Bool = false,
        labelsDiffers: Bool = false,
        confidenceDiffers: Bool = false,
        whitelistEligible: Bool = false,
        preferV1Enabled: Bool = false,
        v1SelectedAsPrimary: Bool = false,
        fallbackUsed: Bool = true,
        legacy: SolutionEngineLegacySnapshot? = nil,
        solutionV1: SolutionEngineV1Snapshot? = nil,
        reasoningShadow: SolutionReasoningShadowReport? = nil,
        debugLines: [String] = []
    ) {
        self.enabled = enabled
        self.compared = compared
        self.hasMismatch = hasMismatch
        self.mismatchReasons = mismatchReasons
        self.mismatchSeverity = mismatchSeverity
        self.warningsDiffers = warningsDiffers
        self.waterToAddDiffers = waterToAddDiffers
        self.technologyStepsDiffers = technologyStepsDiffers
        self.packagingDiffers = packagingDiffers
        self.labelsDiffers = labelsDiffers
        self.confidenceDiffers = confidenceDiffers
        self.whitelistEligible = whitelistEligible
        self.preferV1Enabled = preferV1Enabled
        self.v1SelectedAsPrimary = v1SelectedAsPrimary
        self.fallbackUsed = fallbackUsed
        self.legacy = legacy
        self.solutionV1 = solutionV1
        self.reasoningShadow = reasoningShadow
        self.debugLines = debugLines
    }
}

struct DerivedState: Hashable, Codable, Sendable {
    var routeBranch: String?
    var activatedBlocks: [String]
    var calculations: [String: String]
    var ppkSections: [PpkSection]
    var ppkDocument: PpkDocument?
    var rxModel: RxRenderModel?
    var powderTechnology: PowderTechnologyResult?
    var solutionEngineShadowReport: SolutionEngineShadowReport?

    init(
        routeBranch: String? = nil,
        activatedBlocks: [String] = [],
        calculations: [String: String] = [:],
        ppkSections: [PpkSection] = [],
        ppkDocument: PpkDocument? = nil,
        rxModel: RxRenderModel? = nil,
        powderTechnology: PowderTechnologyResult? = nil,
        solutionEngineShadowReport: SolutionEngineShadowReport? = nil
    ) {
        self.routeBranch = routeBranch
        self.activatedBlocks = activatedBlocks
        self.calculations = calculations
        self.ppkSections = ppkSections
        self.ppkDocument = ppkDocument
        self.rxModel = rxModel
        self.powderTechnology = powderTechnology
        self.solutionEngineShadowReport = solutionEngineShadowReport
    }
}
