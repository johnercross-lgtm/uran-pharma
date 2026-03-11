import Foundation

final class SolutionEngine {
    private let references: SolutionReferenceStore
    private let ingredientParser = IngredientParser()
    private let substanceResolver = SubstanceResolver()
    private let behaviorResolver = BehaviorProfileResolver()
    private let branchSelector = SolutionBranchSelector()
    private let systemClassifier = SolutionSystemClassifier()
    private let calculationEngine = SolutionCalculationEngine()
    private let technologyPlanner = TechnologyPlanner()
    private let validationEngine = ValidationEngine()
    private let doseValidator = DoseValidator()
    private let packagingResolver = PackagingResolver()
    private let ppkRenderer = PPKRenderer()

    init(references: SolutionReferenceStore? = nil) throws {
        if let references {
            self.references = references
        } else {
            self.references = try SolutionReferenceStore()
        }
    }

    func process(request: SolutionEngineRequest) -> SolutionEngineResult {
        var context = SolutionEngineContext(request: request)
        context.move(to: .inputReceived)

        let parsed = ingredientParser.parse(request: request, references: references)
        context.parsedInput = parsed
        for warning in parsed.parserWarnings {
            context.appendWarning(warning)
        }
        context.move(to: .inputParsed)

        if parsed.ingredients.isEmpty {
            context.blocked = true
            context.move(to: .blocked)
            return finalize(context: context)
        }

        context.normalizedIngredients = parsed.ingredients.map {
            SolutionNormalizedIngredient(
                id: $0.id,
                name: $0.name,
                normalizedName: SolutionReferenceStore.normalizeToken($0.normalizedName),
                presentationKind: $0.presentationKind,
                massG: $0.massG,
                volumeMl: $0.volumeMl,
                concentrationPercent: $0.concentrationPercent,
                ratioDenominator: $0.ratioDenominator,
                isAd: $0.isAd,
                adTargetMl: $0.adTargetMl,
                isTargetSolutionLine: $0.isTargetSolutionLine,
                substanceKey: nil,
                behaviorType: nil
            )
        }
        context.move(to: .ingredientsNormalized)

        let resolved = substanceResolver.resolve(ingredients: context.normalizedIngredients, references: references)
        context.resolvedIngredients = resolved.resolved
        resolved.warnings.forEach { context.appendWarning($0) }
        context.unresolvedRuleExists = context.unresolvedRuleExists || resolved.unresolvedRuleExists
        context.move(to: .substancesResolved)

        let behavior = behaviorResolver.resolve(resolved: context.resolvedIngredients, references: references)
        context.behaviorIngredients = behavior.items
        behavior.warnings.forEach { context.appendWarning($0) }
        context.missingBehaviorProfileExists = context.missingBehaviorProfileExists || behavior.missingBehaviorProfile
        context.unresolvedRuleExists = context.unresolvedRuleExists || behavior.unresolvedRuleExists
        context.normalizedIngredients = behavior.items.map { item in
            var base = item.resolved.base
            base.substanceKey = item.resolved.substanceKey
            base.behaviorType = item.behavior?.behaviorType
            return base
        }
        context.move(to: .behaviorProfilesAttached)

        guard let parsedInput = context.parsedInput else {
            context.blocked = true
            context.appendWarning(
                SolutionWarning(
                    code: "internal_missing_parsed_input",
                    severity: .critical,
                    message: "Parsed input unexpectedly missing",
                    state: .routeResolved
                )
            )
            context.move(to: .blocked)
            return finalize(context: context)
        }

        let route = branchSelector.resolveRoute(parsedInput: parsedInput, request: request, references: references)
        context.routeResolution = route.resolution
        route.warnings.forEach { context.appendWarning($0) }
        context.move(to: .routeResolved)

        context.move(to: .formClassified)

        guard let routeResolution = context.routeResolution else {
            context.blocked = true
            context.appendWarning(
                SolutionWarning(
                    code: "route_resolution_missing",
                    severity: .critical,
                    message: "Route resolution missing",
                    state: .solutionBranchSelected
                )
            )
            context.move(to: .blocked)
            return finalize(context: context)
        }

        let branch = branchSelector.selectBranch(
            items: context.behaviorIngredients,
            route: routeResolution,
            request: request,
            references: references
        )
        context.branchResolution = branch.resolution
        branch.warnings.forEach { context.appendWarning($0) }
        context.blocked = context.blocked || branch.blocked
        context.routeConflictExists = context.routeConflictExists || branch.routeConflict
        context.move(to: .solutionBranchSelected)

        guard let branchResolution = context.branchResolution else {
            context.blocked = true
            context.appendWarning(
                SolutionWarning(
                    code: "branch_resolution_missing",
                    severity: .critical,
                    message: "Branch resolution missing",
                    state: .preCalcChecksDone
                )
            )
            context.move(to: .blocked)
            return finalize(context: context)
        }

        context.solutionProfile = systemClassifier.classify(
            items: context.behaviorIngredients,
            branch: branchResolution,
            forceReferenceConcentrate: request.forceReferenceConcentrate ?? [:]
        )

        let preCalc = branchSelector.runPreCalculationChecks(
            parsedInput: parsedInput,
            items: context.behaviorIngredients,
            branch: branchResolution,
            profile: context.solutionProfile
        )
        preCalc.warnings.forEach { context.appendWarning($0) }
        context.blocked = context.blocked || preCalc.blocked
        context.fallbackTargetUsed = context.fallbackTargetUsed || preCalc.fallbackTargetUsed
        context.calculations.targetVolumeMl = preCalc.targetVolumeMl
        context.move(to: .preCalcChecksDone)

        let forceConcentrateMap = request.forceReferenceConcentrate ?? [:]
        let calculations = calculationEngine.calculate(
            items: context.behaviorIngredients,
            branch: branchResolution,
            targetVolumeMl: preCalc.targetVolumeMl,
            profile: context.solutionProfile,
            forceReferenceConcentrate: forceConcentrateMap
        )
        context.calculations = calculations.trace
        calculations.warnings.forEach { context.appendWarning($0) }
        context.blocked = context.blocked || calculations.blocked
        context.move(to: .coreCalculationsDone)

        let technology = technologyPlanner.plan(
            items: context.behaviorIngredients,
            branch: branchResolution,
            profile: context.solutionProfile,
            targetVolumeMl: context.calculations.targetVolumeMl
        )
        context.technologySteps = technology.steps
        context.technologyFlags = technology.flags
        technology.warnings.forEach { context.appendWarning($0) }
        context.move(to: .technologyPlanBuilt)

        let validation = validationEngine.validate(
            items: context.behaviorIngredients,
            branch: branchResolution,
            profile: context.solutionProfile,
            route: routeResolution,
            calculations: context.calculations,
            technologyFlags: context.technologyFlags,
            references: references
        )
        validation.warnings.forEach { context.appendWarning($0) }
        context.blocked = context.blocked || validation.blocked
        context.unresolvedRuleExists = context.unresolvedRuleExists || validation.unresolvedRuleExists
        if context.warnings.contains(where: { $0.code == "unresolved_substance" }),
           !context.warnings.contains(where: { $0.code == "unresolved_rule_hidden" }) {
            context.appendWarning(
                SolutionWarning(
                    code: "unresolved_rule_hidden",
                    severity: .warning,
                    message: "Unresolved rule exists; exact confidence is forbidden",
                    state: .validationDone
                )
            )
        }
        context.move(to: .validationDone)

        let dose = doseValidator.validate(
            signa: parsedInput.signa,
            route: routeResolution,
            items: context.behaviorIngredients,
            calculations: context.calculations,
            references: references
        )
        context.doseControl = dose.dose
        dose.warnings.forEach { context.appendWarning($0) }
        context.move(to: .doseControlDone)

        let packaging = packagingResolver.resolve(
            items: context.behaviorIngredients,
            route: routeResolution,
            branch: branchResolution,
            profile: context.solutionProfile
        )
        context.packaging = packaging.packaging
        packaging.warnings.forEach { context.appendWarning($0) }
        context.move(to: .packagingAndStorageDone)

        let rendered = ppkRenderer.render(
            parsedInput: parsedInput,
            branch: branchResolution,
            profile: context.solutionProfile,
            route: routeResolution,
            calculations: context.calculations,
            technologySteps: context.technologySteps,
            warnings: context.warnings,
            packaging: context.packaging,
            references: references
        )
        context.ppkDocument = rendered.document
        rendered.warnings.forEach { context.appendWarning($0) }
        context.move(to: .ppcRendered)

        context.move(to: .finalResultEmitted)
        return finalize(context: context)
    }

    private func finalize(context: SolutionEngineContext) -> SolutionEngineResult {
        let confidence = resolveConfidence(context: context)
        let branch = context.branchResolution?.branch
        let route = context.routeResolution?.route

        let state: SolutionEngineState
        if confidence == .blocked {
            state = .blocked
        } else if !context.warnings.isEmpty {
            state = .partialWithWarnings
        } else {
            state = .finalResultEmitted
        }

        let validationReport = context.warnings.filter { warning in
            warning.state == .validationDone || warning.state == .solutionBranchSelected || warning.state == .preCalcChecksDone
        }

        return SolutionEngineResult(
            classification: context.branchResolution?.classification ?? "solution",
            solutionBranch: branch,
            route: route,
            solutionProfile: context.solutionProfile,
            normalizedIngredients: context.normalizedIngredients,
            calculationTrace: context.calculations,
            technologySteps: context.technologySteps,
            technologyFlags: context.technologyFlags,
            validationReport: validationReport,
            doseControl: context.doseControl,
            packaging: context.packaging,
            warnings: context.warnings,
            ppkDocument: context.ppkDocument,
            confidence: confidence,
            debugTrace: context.debugTrace,
            state: state
        )
    }

    private func resolveConfidence(context: SolutionEngineContext) -> SolutionEngineConfidence {
        if context.blocked {
            return .blocked
        }

        if context.fallbackTargetUsed
            || (context.routeResolution?.usedFallback == true)
            || context.warnings.contains(where: { $0.code == "unresolved_rule_hidden" }) {
            return .heuristic
        }

        if context.request.structuredInput != nil,
           context.missingBehaviorProfileExists {
            return .heuristic
        }

        if !context.warnings.isEmpty {
            return .approximate
        }

        return .exact
    }
}
