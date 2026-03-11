import Foundation

// MARK: - Core Input Models

struct ParsedRecipeIngredient: Hashable, Codable, Sendable {
    var name: String
    var mass: Double?
    var volumeMl: Double?
    var isAd: Bool
    var adTargetMl: Double?

    init(name: String, mass: Double? = nil, volumeMl: Double? = nil, isAd: Bool = false, adTargetMl: Double? = nil) {
        self.name = name
        self.mass = mass
        self.volumeMl = volumeMl
        self.isAd = isAd
        self.adTargetMl = adTargetMl
    }
}

struct ParsedRecipe: Hashable, Codable, Sendable {
    var ingredients: [ParsedRecipeIngredient]
    var totalVolume: Double?
    var containsLiquidVehicle: Bool
    var containsAquaPurificata: Bool
    var routeHint: String?

    init(
        ingredients: [ParsedRecipeIngredient],
        totalVolume: Double? = nil,
        containsLiquidVehicle: Bool? = nil,
        containsAquaPurificata: Bool? = nil,
        routeHint: String? = nil
    ) {
        self.ingredients = ingredients
        self.totalVolume = totalVolume
        self.routeHint = routeHint

        if let containsLiquidVehicle {
            self.containsLiquidVehicle = containsLiquidVehicle
        } else {
            self.containsLiquidVehicle = ingredients.contains { ingredient in
                ingredient.volumeMl != nil || ingredient.isAd || (ingredient.adTargetMl ?? 0) > 0
            }
        }

        if let containsAquaPurificata {
            self.containsAquaPurificata = containsAquaPurificata
        } else {
            self.containsAquaPurificata = ingredients.contains { ingredient in
                SolutionReferenceStore.normalizeToken(ingredient.name).contains("aqua purificata")
            }
        }
    }

    func hasAdClause(for ingredientName: String) -> Bool {
        let target = SolutionReferenceStore.normalizeToken(ingredientName)
        return ingredients.contains { ingredient in
            let candidate = SolutionReferenceStore.normalizeToken(ingredient.name)
            return candidate == target && ingredient.isAd
        }
    }

    var inferredTargetVolumeMl: Double? {
        if let totalVolume, totalVolume > 0 { return totalVolume }
        return ingredients.compactMap(\.adTargetMl).first(where: { $0 > 0 })
    }
}

// MARK: - Reasoning Models

enum RxReasoningIngredientRole: String, Codable, Sendable {
    case active
    case solvent
    case preservative
    case stabilizer
    case corrigent
    case vehicle
    case unknown
}

struct NormalizedIngredient: Hashable, Codable, Sendable {
    var id: String
    var name: String
    var mass: Double?
    var volumeMl: Double?
    var role: RxReasoningIngredientRole = .unknown
}

enum RxForm: String, Codable, Sendable {
    case solution
    case powder
    case ointment
}

enum RxRoute: String, Codable, Sendable {
    case oral
    case external
}

enum SolutionBranch: String, Codable, Sendable {
    case aqueousTrueSolution = "aqueous_true_solution"
    case suspension = "suspension"
}

enum RxReasoningWarningSeverity: String, Codable, Sendable {
    case info
    case warning
    case blocking
}

struct RxWarning: Hashable, Codable, Sendable {
    var code: String
    var severity: RxReasoningWarningSeverity
    var message: String
}

struct SafetyReport: Hashable, Codable, Sendable {
    var hasCriticalRisks: Bool = false
    var notes: [String] = []
}

struct PackagingPlan: Hashable, Codable, Sendable {
    var container: [String] = []
    var labels: [String] = []
    var storage: [String] = []
}

final class TechnologyPlan {
    var useKUO: Bool = false
    var dissolveInPartialWater: Bool = false
    var adjustToFinalVolumeLast: Bool = false
    var activeIngredients: [NormalizedIngredient] = []
    var solventIngredients: [NormalizedIngredient] = []
}

struct RxReasoningContext {
    var parsedRecipe: ParsedRecipe
    var ingredients: [NormalizedIngredient] = []
    var form: RxForm?
    var route: RxRoute?
    var solutionBranch: SolutionBranch?
    var totalVolumeMl: Double?
    var solidsMass: Double = 0
    var solidsPercent: Double?
    var technologyPlan: TechnologyPlan?
    var safetyReport: SafetyReport?
    var packagingPlan: PackagingPlan?
    var warnings: [RxWarning] = []
    var decisionTrace: [String] = []
    var narrative: [String] = []

    mutating func appendWarning(code: String, severity: RxReasoningWarningSeverity = .warning, message: String) {
        warnings.append(RxWarning(code: code, severity: severity, message: message))
        decisionTrace.append("warning:\(code)")
    }
}

// MARK: - Protocol + Orchestrator

protocol RxReasoningNode {
    func evaluate(context: inout RxReasoningContext)
}

final class RxReasoningEngine {
    private let nodes: [RxReasoningNode]

    init(nodes: [RxReasoningNode]) {
        self.nodes = nodes
    }

    func run(recipe: ParsedRecipe) -> RxReasoningContext {
        var context = RxReasoningContext(parsedRecipe: recipe)
        for node in nodes {
            node.evaluate(context: &context)
        }
        return context
    }
}

// MARK: - Registries

enum SolubilityKind {
    case waterSoluble
    case notWaterSoluble
    case unknown
}

struct IngredientIdentity {
    let id: String
    let name: String
}

final class IngredientRegistry {
    private let references: SolutionReferenceStore?

    init(references: SolutionReferenceStore? = nil) {
        self.references = references
    }

    func normalize(name: String) -> IngredientIdentity {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return IngredientIdentity(id: "unknown", name: "Unknown")
        }

        if let references,
           let substanceKey = references.resolveSubstanceKey(for: cleaned) {
            let keyToken = SolutionReferenceStore.normalizeToken(substanceKey)
            let canonical = references.substanceMasterByKey[keyToken]?.name.latNom
                ?? references.resolveSpecCanonicalName(for: cleaned, substanceKey: substanceKey)
                ?? cleaned
            return IngredientIdentity(id: substanceKey, name: canonical)
        }

        let fallbackId = SolutionReferenceStore.normalizeToken(cleaned).replacingOccurrences(of: " ", with: "_")
        return IngredientIdentity(id: fallbackId.isEmpty ? "unknown" : fallbackId, name: cleaned)
    }
}

final class SubstanceRegistry {
    private let references: SolutionReferenceStore?

    init(references: SolutionReferenceStore? = nil) {
        self.references = references
    }

    func isActiveSubstance(id: String) -> Bool {
        classificationType(id: id) == "active"
    }

    func isSolvent(id: String) -> Bool {
        if classificationType(id: id) == "solvent" {
            return true
        }

        guard let references else { return false }
        let behaviorType = references.resolveBehavior(
            for: id.replacingOccurrences(of: "_", with: " "),
            substanceKey: id
        )?.behaviorType.lowercased()

        let solventBehaviorTypes: Set<String> = [
            "purifiedwater", "alcohol", "glycerin", "oil", "volatilesolvent"
        ]
        return solventBehaviorTypes.contains(behaviorType ?? "")
    }

    func isPreservative(id: String) -> Bool {
        hasRoleKeyword(id: id, keywords: ["preserv", "консерв", "консервант"])
    }

    func isStabilizer(id: String) -> Bool {
        hasRoleKeyword(id: id, keywords: ["stabil", "стабил", "стабіліз"])
    }

    func isCorrigent(id: String) -> Bool {
        hasRoleKeyword(id: id, keywords: ["corrig", "корриг", "кориг"])
    }

    private func classificationType(id: String) -> String {
        guard let record = masterRecord(for: id) else { return "" }
        return (record.classification?.type ?? record.classification?.typeRaw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func hasRoleKeyword(id: String, keywords: [String]) -> Bool {
        guard let record = masterRecord(for: id) else { return false }

        let text = [
            record.classification?.typeRaw,
            record.classification?.type,
            record.classification?.byComposition,
            record.classification?.pharmacologicalActivity,
            record.classification?.byNature
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return keywords.contains { text.contains($0) }
    }

    private func masterRecord(for id: String) -> SubstanceMasterRecord? {
        guard let references else { return nil }

        let direct = SolutionReferenceStore.normalizeToken(id)
        if let record = references.substanceMasterByKey[direct] {
            return record
        }

        if let resolved = references.resolveSubstanceKey(for: id) {
            let key = SolutionReferenceStore.normalizeToken(resolved)
            return references.substanceMasterByKey[key]
        }

        return nil
    }
}

final class SolubilityRegistry {
    private let references: SolutionReferenceStore?

    init(references: SolutionReferenceStore? = nil) {
        self.references = references
    }

    func solubility(of id: String) -> SolubilityKind {
        guard let references else { return .unknown }

        if let record = references.resolveSolubility(
            for: id.replacingOccurrences(of: "_", with: " "),
            substanceKey: id
        ) {
            return mapSolubilityToken(record.solubilityInWater)
        }

        // Fallback to behavior table if specific solubility rule is missing.
        if let behavior = references.resolveBehavior(
            for: id.replacingOccurrences(of: "_", with: " "),
            substanceKey: id
        ) {
            return mapSolubilityToken(behavior.solubilityClass)
        }

        let masterKey = SolutionReferenceStore.normalizeToken(id)
        if let master = references.substanceMasterByKey[masterKey] {
            let nameCandidates = [master.name.latGen, master.name.latNom].compactMap { $0 }
            for candidate in nameCandidates {
                if let behavior = references.resolveBehavior(for: candidate, substanceKey: nil) {
                    return mapSolubilityToken(behavior.solubilityClass)
                }
            }
        }

        return .unknown
    }

    private func mapSolubilityToken(_ token: String) -> SolubilityKind {
        switch token.lowercased() {
        case "freely_soluble", "soluble":
            return .waterSoluble
        case "practically_insoluble", "sparingly_soluble", "poorly_soluble", "requires_co_solvent":
            return .notWaterSoluble
        case "soluble_with_conditions", "reference_dependent", "unknown":
            return .unknown
        default:
            return .unknown
        }
    }
}

// MARK: - Nodes

final class FormDetectionNode: RxReasoningNode {
    func evaluate(context: inout RxReasoningContext) {
        if context.parsedRecipe.containsLiquidVehicle {
            context.form = .solution
            context.decisionTrace.append("form=solution")
        } else {
            context.form = .powder
            context.decisionTrace.append("form=powder")
        }

        if let route = route(from: context.parsedRecipe.routeHint) {
            context.route = route
            context.decisionTrace.append("route=\(route.rawValue)")
        } else if context.parsedRecipe.containsAquaPurificata {
            context.route = .oral
            context.decisionTrace.append("route=oral")
        } else {
            context.appendWarning(code: "route_not_resolved", message: "Route was not resolved from recipe context")
        }
    }

    private func route(from hint: String?) -> RxRoute? {
        guard let hint else { return nil }
        let token = SolutionReferenceStore.normalizeToken(hint)
        if token.contains("oral") || token.contains("per os") || token.contains("внутр") {
            return .oral
        }
        if token.contains("external") || token.contains("наруж") || token.contains("зовн") {
            return .external
        }
        return nil
    }
}

final class IngredientIdentityNode: RxReasoningNode {
    private let registry: IngredientRegistry

    init(registry: IngredientRegistry) {
        self.registry = registry
    }

    func evaluate(context: inout RxReasoningContext) {
        context.ingredients = []
        context.solidsMass = 0

        for item in context.parsedRecipe.ingredients {
            let normalized = registry.normalize(name: item.name)
            var ingredient = NormalizedIngredient(
                id: normalized.id,
                name: normalized.name,
                mass: item.mass,
                volumeMl: item.volumeMl
            )

            if ingredient.mass == nil, ingredient.volumeMl == nil, item.isAd {
                ingredient.volumeMl = item.adTargetMl
            }

            context.ingredients.append(ingredient)
            context.solidsMass += max(item.mass ?? 0, 0)
        }

        context.decisionTrace.append("ingredients_normalized")
    }
}

final class IngredientRoleNode: RxReasoningNode {
    private let substanceRegistry: SubstanceRegistry

    init(substanceRegistry: SubstanceRegistry) {
        self.substanceRegistry = substanceRegistry
    }

    func evaluate(context: inout RxReasoningContext) {
        var updated: [NormalizedIngredient] = []

        for var ingredient in context.ingredients {
            let role = resolveRole(for: ingredient, recipe: context.parsedRecipe)
            ingredient.role = role
            updated.append(ingredient)
            context.decisionTrace.append("role:\(ingredient.id)=\(role.rawValue)")

            if role == .unknown {
                context.appendWarning(
                    code: "unknown_ingredient_role",
                    message: "Role is unresolved for ingredient: \(ingredient.name)"
                )
            }
        }

        context.ingredients = updated
    }

    private func resolveRole(for ingredient: NormalizedIngredient, recipe: ParsedRecipe) -> RxReasoningIngredientRole {
        if substanceRegistry.isSolvent(id: ingredient.id) {
            return recipe.hasAdClause(for: ingredient.name) ? .solvent : .vehicle
        }

        if substanceRegistry.isPreservative(id: ingredient.id) {
            return .preservative
        }

        if substanceRegistry.isStabilizer(id: ingredient.id) {
            return .stabilizer
        }

        if substanceRegistry.isCorrigent(id: ingredient.id) {
            return .corrigent
        }

        if substanceRegistry.isActiveSubstance(id: ingredient.id) {
            return .active
        }

        return .unknown
    }
}

final class SolubilityNode: RxReasoningNode {
    private let registry: SolubilityRegistry

    init(registry: SolubilityRegistry) {
        self.registry = registry
    }

    func evaluate(context: inout RxReasoningContext) {
        guard context.form == .solution else { return }

        let analyzable = context.ingredients.filter { ingredient in
            ingredient.role != .solvent && ingredient.role != .vehicle
        }

        if analyzable.isEmpty {
            context.appendWarning(code: "no_solubility_inputs", message: "No analyzable ingredients for solubility check")
            return
        }

        var allWaterSoluble = true
        var hasUnknown = false

        for ingredient in analyzable {
            switch registry.solubility(of: ingredient.id) {
            case .waterSoluble:
                continue
            case .notWaterSoluble:
                allWaterSoluble = false
            case .unknown:
                hasUnknown = true
                context.appendWarning(
                    code: "missing_solubility_rule",
                    message: "Missing solubility rule for \(ingredient.name)"
                )
            }
        }

        if allWaterSoluble && !hasUnknown {
            context.solutionBranch = .aqueousTrueSolution
            context.decisionTrace.append("branch=aqueous_true_solution")
            return
        }

        if !allWaterSoluble {
            context.solutionBranch = .suspension
            context.decisionTrace.append("branch=suspension")
            return
        }

        context.appendWarning(
            code: "branch_unresolved",
            message: "Solution branch unresolved due to missing solubility rules"
        )
    }
}

final class ConcentrationNode: RxReasoningNode {
    func evaluate(context: inout RxReasoningContext) {
        guard let volume = context.parsedRecipe.inferredTargetVolumeMl, volume > 0 else {
            context.appendWarning(code: "missing_total_volume", message: "Total target volume is required for concentration")
            return
        }

        context.totalVolumeMl = volume
        context.solidsPercent = context.solidsMass / volume * 100

        if let percent = context.solidsPercent {
            if percent < 3 {
                context.decisionTrace.append("solids_lt_3_percent")
            } else {
                context.decisionTrace.append("solids_ge_3_percent")
            }
        }
    }
}

final class TechnologyConstraintNode: RxReasoningNode {
    func evaluate(context: inout RxReasoningContext) {
        guard context.form == .solution else { return }

        let plan = TechnologyPlan()

        if let percent = context.solidsPercent {
            plan.useKUO = percent >= 3
            context.decisionTrace.append(percent < 3 ? "kuo_not_required" : "kuo_required")
        }

        plan.dissolveInPartialWater = true
        plan.adjustToFinalVolumeLast = true

        plan.activeIngredients = context.ingredients.filter { $0.role == .active }
        plan.solventIngredients = context.ingredients.filter { $0.role == .solvent || $0.role == .vehicle }

        if plan.solventIngredients.isEmpty {
            context.appendWarning(code: "missing_solvent", message: "No solvent/vehicle ingredient resolved")
        }

        context.technologyPlan = plan
        context.decisionTrace.append("technology_plan_created")
    }
}

final class NarrativeNode: RxReasoningNode {
    func evaluate(context: inout RxReasoningContext) {
        guard context.form == .solution else { return }

        if let percent = context.solidsPercent, percent < 3 {
            context.decisionTrace.append("ppk:kuo_not_required")
        }

        if let plan = context.technologyPlan {
            let activeNames = plan.activeIngredients.map(\.name)
            let solventNames = plan.solventIngredients.map(\.name)

            if !activeNames.isEmpty, !solventNames.isEmpty {
                let solventLabel = solventNames.joined(separator: ", ")
                let activeLabel = activeNames.joined(separator: ", ")
                if let finalVolume = context.totalVolumeMl {
                    context.narrative.append("У частині \(solventLabel) розчинити: \(activeLabel), довести розчинником до \(finalVolume) ml.")
                } else {
                    context.narrative.append("У частині \(solventLabel) розчинити: \(activeLabel), довести до кінцевого об'єму.")
                }
            }
        }

        context.decisionTrace.append("narrative_generated")
    }
}

// MARK: - Engine Builder

extension RxReasoningEngine {
    static func makeDefault(references: SolutionReferenceStore? = nil) -> RxReasoningEngine {
        let ingredientRegistry = IngredientRegistry(references: references)
        let substanceRegistry = SubstanceRegistry(references: references)
        let solubilityRegistry = SolubilityRegistry(references: references)

        return RxReasoningEngine(nodes: [
            FormDetectionNode(),
            IngredientIdentityNode(registry: ingredientRegistry),
            IngredientRoleNode(substanceRegistry: substanceRegistry),
            SolubilityNode(registry: solubilityRegistry),
            ConcentrationNode(),
            TechnologyConstraintNode(),
            NarrativeNode()
        ])
    }
}

// MARK: - Adapter from SolutionEngineRequest

struct ParsedRecipeAdapter {
    static func from(solutionRequest: SolutionEngineRequest) -> ParsedRecipe {
        let ingredients: [ParsedRecipeIngredient]
        if let structured = solutionRequest.structuredInput {
            ingredients = structured.ingredients.map { ingredient in
                ParsedRecipeIngredient(
                    name: ingredient.name,
                    mass: ingredient.massG,
                    volumeMl: ingredient.volumeMl,
                    isAd: ingredient.isAd ?? false,
                    adTargetMl: ingredient.adTargetMl
                )
            }

            return ParsedRecipe(
                ingredients: ingredients,
                totalVolume: structured.targetVolumeMl,
                routeHint: structured.route ?? solutionRequest.route
            )
        }

        return ParsedRecipe(ingredients: [])
    }
}
