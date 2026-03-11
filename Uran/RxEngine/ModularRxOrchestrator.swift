import Foundation

struct ModularRxEngine {
    private let normalizer = RxDraftNormalizer()
    private let analyzer = RxFactsAnalyzer()
    private let router = RxBlockRouter()
    private let registry = RxBlockRegistry.default()
    private let solutionEngine: SolutionEngine?
    private let reasoningEngine: RxReasoningEngine
    private struct ShadowComparisonOutcome {
        var reasons: [String]
        var warningsDiffers: Bool
        var waterToAddDiffers: Bool
        var technologyStepsDiffers: Bool
        var packagingDiffers: Bool
        var labelsDiffers: Bool
        var confidenceDiffers: Bool
        var mismatchSeverity: SolutionShadowMismatchSeverity
        var debugLines: [String]
    }
    private struct ReasoningShadowComparisonOutcome {
        var reasons: [String]
        var formDiffers: Bool
        var routeDiffers: Bool
        var branchDiffers: Bool
        var rolesDiffers: Bool
        var solidsPercentDiffers: Bool
        var kuoDiffers: Bool
        var volumeStrategyDiffers: Bool
        var warningsDiffers: Bool
        var decisionTraceDiffers: Bool
        var debugLines: [String]
    }
    private struct SolutionShadowEvaluation {
        var report: SolutionEngineShadowReport?
        var solutionResult: SolutionEngineResult?
    }

    init() {
        solutionEngine = Self.makeSolutionEngine()
        reasoningEngine = Self.makeReasoningEngine()
    }

    func evaluate(draft: ExtempRecipeDraft, isNormalized: Bool = false) -> ModularRxEngineOutput {
        let normalizationResult = isNormalized
            ? RxDraftNormalizationResult(normalizedDraft: draft, issues: [])
            : normalizer.normalize(draft: draft)

        let normalizedDraft = normalizationResult.normalizedDraft
        let facts = analyzer.analyze(draft: normalizedDraft)
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: normalizedDraft)
        var context = RxPipelineContext(normalizedDraft: normalizedDraft, facts: facts)
        context.issues.append(contentsOf: normalizationResult.issues)

        let selectedBlockIds = router.route(draft: normalizedDraft, facts: facts)
        let orderedBlocks = registry.orderedBlocks(for: selectedBlockIds)
        for block in orderedBlocks {
            context.activatedBlocks.append(block.id)
            block.apply(context: &context)
        }

        if !context.techPlan.steps.contains(where: { $0.kind == .packaging }) {
            context.addStep(
                TechStep(
                    kind: .packaging,
                    title: "Фасування",
                    ingredientIds: context.draft.ingredients.map(\.id),
                    isCritical: true
                )
            )
        }
        if !context.techPlan.steps.contains(where: { $0.kind == .labeling }) {
            context.addStep(TechStep(kind: .labeling, title: "Маркування", isCritical: true))
        }

        let nonFinalSteps = context.techPlan.steps.filter { $0.kind != .packaging && $0.kind != .labeling }
        let packagingSteps = context.techPlan.steps.filter { $0.kind == .packaging }
        let labelingSteps = context.techPlan.steps.filter { $0.kind == .labeling }
        context.techPlan.steps = nonFinalSteps + packagingSteps + labelingSteps

        context.rxModel.ingredients = context.draft.ingredients.map { ing in
            var flags: [String] = []
            if ing.isAna { flags.append("Ana") }
            if ing.isQS { flags.append("q.s.") }
            if ing.isAd { flags.append("ad") }

            let latinGen = (ing.refNameLatGen ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let latinNom = (ing.refNameLatNom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName: String = {
                if !latinGen.isEmpty { return latinGen }
                if !latinNom.isEmpty { return latinNom }
                return ing.displayName.isEmpty ? "Subst." : ing.displayName
            }()
            let renderedName: String = {
                guard let token = ing.rpPrefix.latinToken else { return baseName }
                if token.lowercased() == "sol.",
                   context.draft.solutionPercentRepresentsSolventStrength(for: ing) {
                    return baseName
                }
                let lower = baseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lower.hasPrefix(token.lowercased()) { return baseName }
                return "\(token) \(baseName)"
            }()

            return RxIngredientLine(name: renderedName, amount: ing.amountValue, unit: ing.unit, flags: flags)
        }
        if let n = context.draft.numero {
            context.rxModel.dtdCommand = "D.t.d. № \(n)"
        }
        context.rxModel.signa = context.draft.signa

        let ppkDocument = PpkRenderer().buildDocument(
            draft: context.draft,
            plan: context.techPlan,
            issues: context.issues,
            sections: context.ppkSections,
            routeBranch: context.routeBranch,
            activatedBlocks: context.activatedBlocks,
            powderTechnology: context.powderTechnology
        )

        let shadowEvaluation = buildSolutionShadowEvaluation(
            effectiveFormMode: effectiveFormMode,
            draft: normalizedDraft,
            context: context
        )
        var shadowReport = shadowEvaluation.report
        let shouldSelectV1 = shouldSelectV1AsPrimary(
            effectiveFormMode: effectiveFormMode,
            report: shadowReport,
            solutionResult: shadowEvaluation.solutionResult
        )
        if var report = shadowReport {
            report.preferV1Enabled = isLiquidFormModeForSolutionEngine(effectiveFormMode)
            report.v1SelectedAsPrimary = shouldSelectV1
            report.fallbackUsed = !shouldSelectV1
            report.debugLines.append("selection_policy=liquid_forms_primary")
            report.debugLines.append("liquid_form_mode=\(isLiquidFormModeForSolutionEngine(effectiveFormMode))")
            report.debugLines.append("v1_selected_as_primary=\(shouldSelectV1)")
            shadowReport = report
        }

        let derived = DerivedState(
            routeBranch: context.routeBranch,
            activatedBlocks: context.activatedBlocks,
            calculations: context.calculations,
            ppkSections: context.ppkSections,
            ppkDocument: ppkDocument,
            rxModel: context.rxModel,
            powderTechnology: context.powderTechnology,
            solutionEngineShadowReport: shadowReport
        )
        let legacyOutput = ModularRxEngineOutput(techPlan: context.techPlan, issues: context.issues, derived: derived)
        guard shouldSelectV1,
              let solutionResult = shadowEvaluation.solutionResult,
              let shadowReport else {
            return legacyOutput
        }

        return makePreferredV1Output(
            legacyOutput: legacyOutput,
            solutionResult: solutionResult,
            shadowReport: shadowReport
        )
    }

    private func buildSolutionShadowEvaluation(
        effectiveFormMode: FormMode,
        draft: ExtempRecipeDraft,
        context: RxPipelineContext
    ) -> SolutionShadowEvaluation {
        guard isLiquidFormModeForSolutionEngine(effectiveFormMode) else {
            return SolutionShadowEvaluation(report: nil, solutionResult: nil)
        }

        let legacy = makeLegacySnapshot(context: context)
        let request = makeSolutionRequest(draft: draft, facts: context.facts)
        let reasoningShadow = buildReasoningShadowReport(
            draft: draft,
            context: context,
            request: request,
            legacy: legacy
        )
        guard let solutionEngine else {
            let report = SolutionEngineShadowReport(
                enabled: true,
                compared: false,
                hasMismatch: false,
                mismatchReasons: ["solution_engine_unavailable"],
                mismatchSeverity: .none,
                warningsDiffers: false,
                waterToAddDiffers: false,
                technologyStepsDiffers: false,
                packagingDiffers: false,
                labelsDiffers: false,
                confidenceDiffers: false,
                whitelistEligible: false,
                preferV1Enabled: false,
                v1SelectedAsPrimary: false,
                fallbackUsed: true,
                legacy: legacy,
                solutionV1: nil,
                reasoningShadow: reasoningShadow,
                debugLines: [
                    "solution_engine_unavailable",
                    "fallback_used=true",
                    "legacy.routeBranch=\(legacy.routeBranch ?? "nil")",
                    "reasoning.compared=\(reasoningShadow.compared)",
                    "reasoning.mismatch_reasons=\(debugList(reasoningShadow.mismatchReasons))"
                ]
            )
            return SolutionShadowEvaluation(report: report, solutionResult: nil)
        }

        let result = solutionEngine.process(request: request)
        let solutionV1 = makeSolutionSnapshot(result: result)
        let outcome = compareShadow(legacy: legacy, solutionV1: solutionV1)
        let whitelistEligible = isWhitelistedVariant(solutionV1: solutionV1)

        var debugLines = outcome.debugLines
        let forcedConcentrateKeys = uniqueSorted(Array((request.forceReferenceConcentrate ?? [:]).keys))
        debugLines.append("forced_concentrates=\(debugList(forcedConcentrateKeys))")
        debugLines.append("whitelist_eligible=\(whitelistEligible)")
        if !whitelistEligible,
           solutionV1.warningCodes.contains(where: { $0.lowercased() == "controlled_class_a_present" }) {
            debugLines.append("whitelist_blocked_reason=list_a_controlled_substance")
        }
        debugLines.append("mismatch_severity=\(outcome.mismatchSeverity.rawValue)")
        debugLines.append("reasoning.compared=\(reasoningShadow.compared)")
        debugLines.append("reasoning.has_mismatch=\(reasoningShadow.hasMismatch)")
        debugLines.append("reasoning.mismatch_reasons=\(debugList(reasoningShadow.mismatchReasons))")

        let report = SolutionEngineShadowReport(
            enabled: true,
            compared: true,
            hasMismatch: !outcome.reasons.isEmpty,
            mismatchReasons: outcome.reasons,
            mismatchSeverity: outcome.mismatchSeverity,
            warningsDiffers: outcome.warningsDiffers,
            waterToAddDiffers: outcome.waterToAddDiffers,
            technologyStepsDiffers: outcome.technologyStepsDiffers,
            packagingDiffers: outcome.packagingDiffers,
            labelsDiffers: outcome.labelsDiffers,
            confidenceDiffers: outcome.confidenceDiffers,
            whitelistEligible: whitelistEligible,
            preferV1Enabled: false,
            v1SelectedAsPrimary: false,
            fallbackUsed: true,
            legacy: legacy,
            solutionV1: solutionV1,
            reasoningShadow: reasoningShadow,
            debugLines: debugLines
        )
        return SolutionShadowEvaluation(report: report, solutionResult: result)
    }

    private func makeLegacySnapshot(context: RxPipelineContext) -> SolutionEngineLegacySnapshot {
        let blockingCodes = context.issues
            .filter { $0.severity == .blocking }
            .map(\.code)
        let warningCodes = context.issues
            .filter { $0.severity == .warning }
            .map(\.code)
        let allCodes = context.issues.map(\.code)
        let packagingInfo = extractLegacyPackagingAndLabels(sections: context.ppkSections)
        let confidence = !blockingCodes.isEmpty ? "blocked" : (!warningCodes.isEmpty ? "approximate" : "exact")

        return SolutionEngineLegacySnapshot(
            routeBranch: context.routeBranch,
            activatedBlocks: context.activatedBlocks,
            blockingIssueCodes: uniqueSorted(blockingCodes),
            warningIssueCodes: uniqueSorted(warningCodes),
            allIssueCodes: uniqueSorted(allCodes),
            confidence: confidence,
            calculationKeys: context.calculations.keys.sorted(),
            waterToAddMl: resolveLegacyWaterToAddMl(calculations: context.calculations),
            techStepKinds: uniqueSorted(context.techPlan.steps.map { $0.kind.rawValue }),
            technologySteps: uniqueSorted(context.techPlan.steps.map(\.title)),
            packaging: packagingInfo.packaging,
            labels: packagingInfo.labels
        )
    }

    private func makeSolutionSnapshot(result: SolutionEngineResult) -> SolutionEngineV1Snapshot {
        let warningCodes = result.warnings.map(\.code)
        let criticalCodes = result.warnings
            .filter { $0.severity == .critical }
            .map(\.code)

        return SolutionEngineV1Snapshot(
            route: result.route,
            branch: result.solutionBranch,
            confidence: result.confidence.rawValue,
            state: result.state.rawValue,
            warningCodes: uniqueSorted(warningCodes),
            criticalWarningCodes: uniqueSorted(criticalCodes),
            technologyFlags: result.technologyFlags,
            technologySteps: result.technologySteps,
            packaging: result.packaging.packaging,
            labels: result.packaging.labels,
            storage: result.packaging.storage,
            waterToAddMl: result.calculationTrace.waterToAddMl
        )
    }

    private func compareShadow(
        legacy: SolutionEngineLegacySnapshot,
        solutionV1: SolutionEngineV1Snapshot
    ) -> ShadowComparisonOutcome {
        var reasons: [String] = []
        var warningsDiffers = false
        var waterToAddDiffers = false
        var technologyStepsDiffers = false
        var packagingDiffers = false
        var labelsDiffers = false
        var confidenceDiffers = false

        let legacyBlocking = !legacy.blockingIssueCodes.isEmpty
        let solutionBlocked = solutionV1.confidence == "blocked"
        if legacyBlocking != solutionBlocked {
            reasons.append("blocking_state_differs")
        }

        let legacyBranch = mapLegacyBranch(legacy: legacy)
        let newBranch = solutionV1.branch
        if let legacyBranch, let newBranch {
            if !branchesCompatible(legacy: legacyBranch, solutionV1: newBranch) {
                reasons.append("branch_differs:\(legacyBranch)->\(newBranch)")
            }
        } else if legacyBranch != newBranch {
            reasons.append("branch_differs:\(legacyBranch ?? "nil")->\(newBranch ?? "nil")")
        }

        let legacyWarnings = uniqueSorted(legacy.allIssueCodes.map { $0.uppercased() })
        let solutionWarnings = uniqueSorted(solutionV1.warningCodes.map { $0.uppercased() })
        warningsDiffers = legacyWarnings != solutionWarnings
        if warningsDiffers {
            reasons.append("warnings_differs")
        }

        waterToAddDiffers = !optionalDoublesEqual(
            legacy.waterToAddMl,
            solutionV1.waterToAddMl,
            tolerance: 0.05
        )
        if waterToAddDiffers {
            reasons.append("water_to_add_differs")
        }

        let legacyTechnology = normalizeStringSet(legacy.technologySteps)
        let solutionTechnology = normalizeStringSet(solutionV1.technologySteps)
        technologyStepsDiffers = legacyTechnology != solutionTechnology
        if technologyStepsDiffers {
            reasons.append("technology_steps_differs")
        }

        let legacyPackaging = normalizeStringSet(legacy.packaging)
        let solutionPackaging = normalizeStringSet(solutionV1.packaging)
        packagingDiffers = legacyPackaging != solutionPackaging
        if packagingDiffers {
            reasons.append("packaging_differs")
        }

        let legacyLabels = normalizeStringSet(legacy.labels)
        let solutionLabels = normalizeStringSet(solutionV1.labels)
        labelsDiffers = legacyLabels != solutionLabels
        if labelsDiffers {
            reasons.append("labels_differs")
        }

        confidenceDiffers = normalizedConfidence(legacy.confidence) != normalizedConfidence(solutionV1.confidence)
        if confidenceDiffers {
            reasons.append("confidence_differs")
        }

        var debugLines: [String] = [
            "legacy.routeBranch=\(legacy.routeBranch ?? "nil")",
            "legacy.mappedBranch=\(legacyBranch ?? "nil")",
            "solution.route=\(solutionV1.route ?? "nil")",
            "solution.branch=\(newBranch ?? "nil")",
            "legacy.confidence=\(legacy.confidence)",
            "solution.confidence=\(solutionV1.confidence)",
            "legacy.warning_codes=\(debugList(legacyWarnings))",
            "solution.warning_codes=\(debugList(solutionWarnings))",
            "legacy.water_to_add_ml=\(debugOptionalDouble(legacy.waterToAddMl))",
            "solution.water_to_add_ml=\(debugOptionalDouble(solutionV1.waterToAddMl))",
            "legacy.technology_steps=\(debugList(legacyTechnology))",
            "solution.technology_steps=\(debugList(solutionTechnology))",
            "legacy.packaging=\(debugList(legacyPackaging))",
            "solution.packaging=\(debugList(solutionPackaging))",
            "legacy.labels=\(debugList(legacyLabels))",
            "solution.labels=\(debugList(solutionLabels))",
            "mismatch_reasons=\(debugList(reasons))"
        ]

        if let legacyJSON = jsonString(legacy) {
            debugLines.append("legacy_snapshot_json=\(legacyJSON)")
        }
        if let solutionJSON = jsonString(solutionV1) {
            debugLines.append("solution_snapshot_json=\(solutionJSON)")
        }

        let mismatchSeverity = classifyMismatchSeverity(
            reasons: reasons,
            legacy: legacy,
            solutionV1: solutionV1
        )
        debugLines.append("mismatch_severity=\(mismatchSeverity.rawValue)")

        return ShadowComparisonOutcome(
            reasons: reasons,
            warningsDiffers: warningsDiffers,
            waterToAddDiffers: waterToAddDiffers,
            technologyStepsDiffers: technologyStepsDiffers,
            packagingDiffers: packagingDiffers,
            labelsDiffers: labelsDiffers,
            confidenceDiffers: confidenceDiffers,
            mismatchSeverity: mismatchSeverity,
            debugLines: debugLines
        )
    }

    private func buildReasoningShadowReport(
        draft: ExtempRecipeDraft,
        context: RxPipelineContext,
        request: SolutionEngineRequest,
        legacy: SolutionEngineLegacySnapshot
    ) -> SolutionReasoningShadowReport {
        let legacySnapshot = makeLegacyReasoningSnapshot(
            draft: draft,
            context: context,
            request: request,
            legacy: legacy
        )

        let parsedRecipe = ParsedRecipeAdapter.from(solutionRequest: request)
        let reasoningContext = reasoningEngine.run(recipe: parsedRecipe)
        let reasoningSnapshot = makeReasoningSnapshot(context: reasoningContext)

        let outcome = compareReasoningShadow(
            legacy: legacySnapshot,
            reasoning: reasoningSnapshot,
            allowBuretteCompatibility: !(request.forceReferenceConcentrate ?? [:]).isEmpty
        )

        var reasons = outcome.reasons
        let warningCodes = Set(reasoningSnapshot.warnings.map { $0.lowercased() })
        if warningCodes.contains("unknown_ingredient_role") {
            reasons.append("warning.role_unknown")
        }
        if warningCodes.contains("missing_solubility_rule") {
            reasons.append("warning.solubility_unknown")
        }
        reasons = uniqueSorted(reasons)

        var debugLines = outcome.debugLines
        let forcedConcentrateKeys = uniqueSorted(Array((request.forceReferenceConcentrate ?? [:]).keys))
        debugLines.append("reasoning.forced_concentrates=\(debugList(forcedConcentrateKeys))")
        debugLines.append("reasoning.warning_codes=\(debugList(reasoningSnapshot.warnings))")
        debugLines.append("reasoning.mismatch_reasons=\(debugList(reasons))")
        if let legacyJSON = jsonString(legacySnapshot) {
            debugLines.append("reasoning.legacy_snapshot_json=\(legacyJSON)")
        }
        if let reasoningJSON = jsonString(reasoningSnapshot) {
            debugLines.append("reasoning.snapshot_json=\(reasoningJSON)")
        }

        return SolutionReasoningShadowReport(
            enabled: true,
            compared: true,
            hasMismatch: !reasons.isEmpty,
            mismatchReasons: reasons,
            formDiffers: outcome.formDiffers,
            routeDiffers: outcome.routeDiffers,
            branchDiffers: outcome.branchDiffers,
            rolesDiffers: outcome.rolesDiffers,
            solidsPercentDiffers: outcome.solidsPercentDiffers,
            kuoDiffers: outcome.kuoDiffers,
            volumeStrategyDiffers: outcome.volumeStrategyDiffers,
            warningsDiffers: outcome.warningsDiffers,
            decisionTraceDiffers: outcome.decisionTraceDiffers,
            legacy: legacySnapshot,
            reasoning: reasoningSnapshot,
            debugLines: debugLines
        )
    }

    private func makeLegacyReasoningSnapshot(
        draft: ExtempRecipeDraft,
        context: RxPipelineContext,
        request: SolutionEngineRequest,
        legacy: SolutionEngineLegacySnapshot
    ) -> SolutionLegacyReasoningSnapshot {
        let route = request.structuredInput?.route ?? inferSolutionRoute(draft: draft, facts: context.facts)
        let branch = mapLegacyBranch(legacy: legacy)
        let solidsPercent = computeSolidsPercent(from: request)
        let useKUO = inferLegacyKuoUsage(context: context, solidsPercent: solidsPercent)
        let adjustToFinalVolumeLast = inferLegacyFinalAdjustment(context: context)

        var roles: [String: String] = [:]
        for ingredient in draft.ingredients {
            let name = preferredIngredientName(ingredient)
            let key = normalizeForCompare(name)
            guard !key.isEmpty else { continue }

            let mappedRole: String
            switch ingredient.role {
            case .active:
                mappedRole = "active"
            case .solvent:
                mappedRole = (ingredient.isAd || ingredient.isQS) ? "solvent" : "vehicle"
            case .base:
                mappedRole = "vehicle"
            case .excipient:
                mappedRole = "unknown"
            case .other:
                mappedRole = (ingredient.isAd || ingredient.isQS) ? "solvent" : "unknown"
            }
            roles[key] = mappedRole
        }

        let warningCodes = uniqueSorted(context.issues.map { $0.code.lowercased() })

        var trace: [String] = [
            "form=solution",
            "route=\(route)",
            "branch=\(branch ?? "nil")"
        ]
        for key in roles.keys.sorted() {
            trace.append("role:\(key)=\(roles[key] ?? "unknown")")
        }
        if let solidsPercent {
            trace.append("solids_percent=\(formatDouble(solidsPercent))")
        }
        if let useKUO {
            trace.append("kuo=\(useKUO)")
        } else {
            trace.append("kuo=nil")
        }
        trace.append("final_adjustment=\(adjustToFinalVolumeLast)")

        return SolutionLegacyReasoningSnapshot(
            form: "solution",
            route: route,
            branch: branch,
            roles: roles,
            solidsPercent: solidsPercent,
            useKUO: useKUO,
            adjustToFinalVolumeLast: adjustToFinalVolumeLast,
            warnings: warningCodes,
            decisionTrace: trace
        )
    }

    private func makeReasoningSnapshot(context: RxReasoningContext) -> SolutionReasoningSnapshot {
        var roles: [String: String] = [:]
        for ingredient in context.ingredients {
            let key = normalizeForCompare(ingredient.name)
            guard !key.isEmpty else { continue }
            roles[key] = ingredient.role.rawValue
        }

        let warnings = uniqueSorted(context.warnings.map { $0.code.lowercased() })
        return SolutionReasoningSnapshot(
            form: context.form?.rawValue,
            route: context.route?.rawValue,
            branch: context.solutionBranch?.rawValue,
            roles: roles,
            solidsPercent: context.solidsPercent,
            useKUO: context.technologyPlan?.useKUO,
            adjustToFinalVolumeLast: context.technologyPlan?.adjustToFinalVolumeLast,
            warnings: warnings,
            decisionTrace: context.decisionTrace
        )
    }

    private func compareReasoningShadow(
        legacy: SolutionLegacyReasoningSnapshot,
        reasoning: SolutionReasoningSnapshot,
        allowBuretteCompatibility: Bool
    ) -> ReasoningShadowComparisonOutcome {
        var reasons: [String] = []
        var formDiffers = false
        var routeDiffers = false
        var branchDiffers = false
        var rolesDiffers = false
        var solidsPercentDiffers = false
        var kuoDiffers = false
        var volumeStrategyDiffers = false
        var warningsDiffers = false
        var decisionTraceDiffers = false

        if normalizeForCompare(legacy.form ?? "") != normalizeForCompare(reasoning.form ?? "") {
            formDiffers = true
            reasons.append("form_differs")
        }
        if normalizeForCompare(legacy.route ?? "") != normalizeForCompare(reasoning.route ?? "") {
            routeDiffers = true
            reasons.append("route_differs")
        }
        let legacyBranchNormalized = normalizeForCompare(legacy.branch ?? "")
        let reasoningBranchNormalized = normalizeForCompare(reasoning.branch ?? "")
        let branchIsCompatibleForBurette: Bool = {
            guard allowBuretteCompatibility else { return false }
            return legacyBranchNormalized == "aqueous_burette_solution"
                && reasoningBranchNormalized == "aqueous_true_solution"
        }()
        if legacyBranchNormalized != reasoningBranchNormalized && !branchIsCompatibleForBurette {
            branchDiffers = true
            reasons.append("branch_differs")
        }

        let roleKeys = Set(legacy.roles.keys).union(reasoning.roles.keys)
        for key in roleKeys.sorted() {
            let legacyRole = legacy.roles[key] ?? "unknown"
            let reasoningRole = reasoning.roles[key] ?? "unknown"
            if legacyRole != reasoningRole {
                rolesDiffers = true
                reasons.append("role_differs:\(key)")
            }
        }

        solidsPercentDiffers = !optionalDoublesEqual(legacy.solidsPercent, reasoning.solidsPercent, tolerance: 0.05)
        if solidsPercentDiffers {
            reasons.append("solids_percent_differs")
        }

        kuoDiffers = legacy.useKUO != reasoning.useKUO
        if kuoDiffers {
            reasons.append("kuo_differs")
        }

        volumeStrategyDiffers = legacy.adjustToFinalVolumeLast != reasoning.adjustToFinalVolumeLast
        if volumeStrategyDiffers {
            reasons.append("volume_strategy_differs")
        }

        warningsDiffers = uniqueSorted(legacy.warnings) != uniqueSorted(reasoning.warnings)
        if warningsDiffers {
            reasons.append("warning_differs")
        }

        decisionTraceDiffers = legacy.decisionTrace != reasoning.decisionTrace
        if decisionTraceDiffers {
            reasons.append("decision_trace_differs")
        }

        var debugLines: [String] = [
            "reasoning.legacy.form=\(legacy.form ?? "nil")",
            "reasoning.v1.form=\(reasoning.form ?? "nil")",
            "reasoning.legacy.route=\(legacy.route ?? "nil")",
            "reasoning.v1.route=\(reasoning.route ?? "nil")",
            "reasoning.legacy.branch=\(legacy.branch ?? "nil")",
            "reasoning.v1.branch=\(reasoning.branch ?? "nil")",
            "reasoning.legacy.roles=\(debugRoleMap(legacy.roles))",
            "reasoning.v1.roles=\(debugRoleMap(reasoning.roles))",
            "reasoning.legacy.solids_percent=\(debugOptionalDouble(legacy.solidsPercent))",
            "reasoning.v1.solids_percent=\(debugOptionalDouble(reasoning.solidsPercent))",
            "reasoning.legacy.kuo=\(legacy.useKUO.map { String($0) } ?? "nil")",
            "reasoning.v1.kuo=\(reasoning.useKUO.map { String($0) } ?? "nil")",
            "reasoning.legacy.final_adjustment=\(legacy.adjustToFinalVolumeLast.map { String($0) } ?? "nil")",
            "reasoning.v1.final_adjustment=\(reasoning.adjustToFinalVolumeLast.map { String($0) } ?? "nil")",
            "reasoning.legacy.warning_codes=\(debugList(legacy.warnings))",
            "reasoning.v1.warning_codes=\(debugList(reasoning.warnings))",
            "reasoning.legacy.trace=\(debugList(legacy.decisionTrace))",
            "reasoning.v1.trace=\(debugList(reasoning.decisionTrace))"
        ]
        debugLines.append("reasoning.mismatch_reasons=\(debugList(uniqueSorted(reasons)))")

        return ReasoningShadowComparisonOutcome(
            reasons: uniqueSorted(reasons),
            formDiffers: formDiffers,
            routeDiffers: routeDiffers,
            branchDiffers: branchDiffers,
            rolesDiffers: rolesDiffers,
            solidsPercentDiffers: solidsPercentDiffers,
            kuoDiffers: kuoDiffers,
            volumeStrategyDiffers: volumeStrategyDiffers,
            warningsDiffers: warningsDiffers,
            decisionTraceDiffers: decisionTraceDiffers,
            debugLines: debugLines
        )
    }

    private func classifyMismatchSeverity(
        reasons: [String],
        legacy: SolutionEngineLegacySnapshot,
        solutionV1: SolutionEngineV1Snapshot
    ) -> SolutionShadowMismatchSeverity {
        guard !reasons.isEmpty else { return .none }

        if reasons.contains("blocking_state_differs") {
            return .critical
        }

        if reasons.contains(where: { $0.hasPrefix("branch_differs:") }) {
            return .critical
        }

        let legacyConfidence = normalizedConfidence(legacy.confidence)
        let v1Confidence = normalizedConfidence(solutionV1.confidence)
        if reasons.contains("confidence_differs"),
           legacyConfidence == "blocked" || v1Confidence == "blocked" {
            return .critical
        }

        if reasons.contains("water_to_add_differs"),
           let lhs = legacy.waterToAddMl,
           let rhs = solutionV1.waterToAddMl,
           abs(lhs - rhs) > 0.5 {
            return .critical
        }

        let legacyBlocking = Set(legacy.blockingIssueCodes.map { $0.uppercased() })
        let solutionCritical = Set(solutionV1.criticalWarningCodes.map { $0.uppercased() })
        if !solutionCritical.subtracting(legacyBlocking).isEmpty {
            return .critical
        }

        return .nonCritical
    }

    private func isWhitelistedVariant(solutionV1: SolutionEngineV1Snapshot) -> Bool {
        guard let branch = solutionV1.branch,
              let route = solutionV1.route else { return false }

        let allowedBranches: Set<String> = [
            "aqueous_true_solution",
            "standard_solution_mix",
            "ready_solution_mix",
            "non_aqueous_solution",
            "volatile_non_aqueous_solution"
        ]
        let allowedRoutes: Set<String> = ["oral", "external"]

        guard allowedBranches.contains(branch), allowedRoutes.contains(route) else { return false }
        guard ["exact", "approximate"].contains(solutionV1.confidence.lowercased()) else { return false }
        guard solutionV1.state != SolutionEngineState.blocked.rawValue else { return false }
        guard solutionV1.criticalWarningCodes.isEmpty else { return false }
        guard !solutionV1.warningCodes.contains(where: { $0.lowercased() == "controlled_class_a_present" }) else { return false }

        return true
    }

    private func isLiquidFormModeForSolutionEngine(_ formMode: FormMode) -> Bool {
        formMode == .solutions || formMode == .drops
    }

    private func shouldSelectV1AsPrimary(
        effectiveFormMode: FormMode,
        report: SolutionEngineShadowReport?,
        solutionResult: SolutionEngineResult?
    ) -> Bool {
        guard isLiquidFormModeForSolutionEngine(effectiveFormMode),
              let report,
              solutionResult != nil else {
            return false
        }
        guard report.compared else { return false }
        guard !report.hasMismatch else { return false }
        guard report.mismatchSeverity != .critical else { return false }

        guard let solutionResult else { return false }
        guard solutionResult.confidence == .exact || solutionResult.confidence == .approximate else {
            return false
        }

        let criticalWarningsExist = solutionResult.warnings.contains { $0.severity == .critical }
        guard !criticalWarningsExist else { return false }

        let fallbackWarningCodes: Set<String> = [
            "unresolved_substance",
            "missing_behavior_profile",
            "unresolved_rule_hidden",
            "zero_water_with_unexplained_ad",
            "negative_water_result",
            "dose_control_required_but_unresolved"
        ]
        let warningCodes = Set(solutionResult.warnings.map { $0.code.lowercased() })
        guard warningCodes.isDisjoint(with: fallbackWarningCodes) else {
            return false
        }

        return true
    }

    private func makePreferredV1Output(
        legacyOutput: ModularRxEngineOutput,
        solutionResult: SolutionEngineResult,
        shadowReport: SolutionEngineShadowReport
    ) -> ModularRxEngineOutput {
        var output = legacyOutput

        let v1TechPlan = makeV1TechPlan(from: solutionResult)
        if !v1TechPlan.steps.isEmpty {
            output.techPlan = v1TechPlan
        }
        output.issues = makeV1Issues(from: solutionResult.warnings)

        var derived = output.derived
        if let mappedRouteBranch = mapV1BranchToLegacyRouteBranch(solutionResult.solutionBranch) {
            derived.routeBranch = mappedRouteBranch
        }
        derived.calculations = makeV1Calculations(
            trace: solutionResult.calculationTrace,
            base: derived.calculations
        )

        let v1Sections = makeV1PpkSections(document: solutionResult.ppkDocument)
        if !v1Sections.isEmpty {
            derived.ppkSections = v1Sections
            var ppkDocument = PpkDocument()
            ppkDocument.control = v1Sections
            derived.ppkDocument = ppkDocument
        }

        derived.solutionEngineShadowReport = shadowReport
        output.derived = derived
        return output
    }

    private func makeV1TechPlan(from result: SolutionEngineResult) -> TechPlan {
        let deduplicatedTitles = uniquePreservingOrder(
            result.technologySteps.map { normalizedV1StepTitle($0) }
                .map { stripListPrefix($0) }
                .filter { !$0.isEmpty }
        )

        var steps = deduplicatedTitles.enumerated().map { index, title in
            return TechStep(
                kind: mapV1StepKind(title),
                title: "\(index + 1). \(title)",
                isCritical: false
            )
        }

        if !steps.contains(where: { $0.kind == .packaging }),
           !result.packaging.packaging.isEmpty {
            steps.append(TechStep(kind: .packaging, title: "Фасовка", isCritical: true))
        }
        if !steps.contains(where: { $0.kind == .labeling }),
           !result.packaging.labels.isEmpty {
            steps.append(TechStep(kind: .labeling, title: "Маркировка", isCritical: true))
        }

        let core = steps.filter { $0.kind != .packaging && $0.kind != .labeling }
        let packaging = steps.filter { $0.kind == .packaging }
        let labeling = steps.filter { $0.kind == .labeling }
        return TechPlan(steps: core + packaging + labeling)
    }

    private func normalizedV1StepTitle(_ rawStep: String) -> String {
        let stripped = stripListPrefix(rawStep)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeForCompare(stripped)

        if matchesAny(normalized, needles: ["direct dissolution", "dissol", "растворен"]) {
            return "Растворение"
        }
        if matchesAny(normalized, needles: ["measure part of the suitable solvent", "part of solvent"]) {
            return "Отмерить часть подходящего растворителя"
        }
        if matchesAny(normalized, needles: ["dissolve acidum boricum separately"]) {
            return "Растворить борную кислоту отдельно"
        }
        if matchesAny(normalized, needles: ["mild heating", "умеренн", "помірн"]) {
            return "При необходимости использовать умеренный нагрев"
        }
        if matchesAny(normalized, needles: ["transfer solution into main vessel", "main vessel"]) {
            return "Перенести раствор в основной сосуд"
        }
        if matchesAny(normalized, needles: ["iodide assisted", "iodidum", "iodum"]) {
            return "Йодидный способ растворения"
        }
        if matchesAny(normalized, needles: ["dissolve in part water", "dissolve_in_part_water"]) {
            return "Растворить в части воды"
        }
        if matchesAny(normalized, needles: ["stirring dissolution", "stirring_dissolution"]) {
            return "Растворять при перемешивании"
        }
        if matchesAny(normalized, needles: ["hot water dissolution", "hot_water_dissolution"]) {
            return "Растворение в горячей воде"
        }
        if matchesAny(normalized, needles: ["cool before qs", "cool_before_qs"]) {
            return "Охладить перед доведением объема"
        }
        if matchesAny(normalized, needles: ["separate dissolution stage", "separate_dissolution_stage"]) {
            return "Отдельная стадия растворения"
        }
        if matchesAny(normalized, needles: ["prepare combined subsolution first", "prepare_combined_subsolution_first"]) {
            return "Сначала приготовить объединенный подраствор"
        }
        if matchesAny(normalized, needles: ["late addition", "late_addition"]) {
            return "Добавить на поздней стадии"
        }
        if matchesAny(normalized, needles: ["no heating", "no_heating"]) {
            return "Без нагревания"
        }
        if matchesAny(normalized, needles: ["filtration if needed", "filtration_if_needed"]) {
            return "Фильтрация при необходимости"
        }
        if matchesAny(normalized, needles: ["switch to other solvent", "switch_to_other_solvent"]) {
            return "Перейти на другой растворитель"
        }
        if matchesAny(normalized, needles: ["prepare primary emulsion", "prepare_primary_emulsion"]) {
            return "Приготовить первичную эмульсию"
        }
        if matchesAny(normalized, needles: ["dilute to final volume", "dilute_to_final_volume"]) {
            return "Довести до конечного объема"
        }
        if matchesAny(normalized, needles: ["label shake before use", "label_shake_before_use"]) {
            return "Указать на этикетке: перед применением взбалтывать"
        }
        if matchesAny(normalized, needles: ["triturate solid", "triturate_solid"]) {
            return "Растереть твердое вещество"
        }
        if matchesAny(normalized, needles: ["add liquid gradually", "add_liquid_gradually"]) {
            return "Добавлять жидкость постепенно"
        }
        if matchesAny(normalized, needles: ["colloid dissolution", "colloid_dissolution"]) {
            return "Коллоидное растворение"
        }
        if matchesAny(normalized, needles: ["mix", "смеш"]) {
            return "Смешивание"
        }
        if matchesAny(normalized, needles: ["bring to volume", "ad ", "довед", "до обем", "до объем"]) {
            return "Доведение объема до требуемого (ad)"
        }
        if matchesAny(normalized, needles: ["filter", "фильтр"]) {
            return "Фильтрация"
        }
        if matchesAny(normalized, needles: ["steril", "стерил"]) {
            return "Стерилизация"
        }
        if matchesAny(normalized, needles: ["packag", "упаков", "фас"]) {
            return "Фасовка"
        }
        if matchesAny(normalized, needles: ["label", "марк"]) {
            return "Маркировка"
        }

        return stripped.isEmpty ? rawStep : stripped
    }

    private func mapV1StepKind(_ step: String) -> TechStepKind {
        let normalized = normalizeForCompare(step)
        if matchesAny(normalized, needles: ["розчин", "раствор", "dissol"]) { return .dissolution }
        if matchesAny(normalized, needles: ["зміш", "mix"]) { return .mixing }
        if matchesAny(normalized, needles: ["довед", "ad ", "volume", "обєм"]) { return .bringToVolume }
        if matchesAny(normalized, needles: ["фільтр", "filter"]) { return .filtration }
        if matchesAny(normalized, needles: ["стерил", "steril"]) { return .sterilization }
        if matchesAny(normalized, needles: ["упаков", "фас", "packag"]) { return .packaging }
        if matchesAny(normalized, needles: ["марку", "label"]) { return .labeling }
        if matchesAny(normalized, needles: ["tritur"]) { return .trituration }
        return .prep
    }

    private func makeV1Issues(from warnings: [SolutionWarning]) -> [RxIssue] {
        warnings.map { warning in
            RxIssue(
                code: warning.code,
                severity: mapWarningSeverity(warning.severity),
                message: warning.message
            )
        }
    }

    private func mapWarningSeverity(_ severity: SolutionWarningSeverity) -> RxIssueSeverity {
        switch severity {
        case .info:
            return .info
        case .warning:
            return .warning
        case .critical:
            return .blocking
        }
    }

    private func mapV1BranchToLegacyRouteBranch(_ branch: String?) -> String? {
        guard let branch else { return nil }
        switch branch {
        case "aqueous_true_solution", "aqueous_burette_solution":
            return "water_solution"
        case "non_aqueous_solution", "volatile_non_aqueous_solution":
            return "non_aqueous_solution"
        case "standard_solution_mix", "ready_solution_mix":
            return "standard_solution"
        default:
            return nil
        }
    }

    private func makeV1Calculations(trace: SolutionCalculationTrace, base: [String: String]) -> [String: String] {
        var calculations = base
        if let target = trace.targetVolumeMl {
            calculations["target_ml"] = formatDouble(target)
            calculations["solution_v1.target_ml"] = formatDouble(target)
        }
        if let water = trace.waterToAddMl {
            calculations["water_to_add_ml"] = formatDouble(water)
            calculations["solution_v1.water_to_add_ml"] = formatDouble(water)
        }
        calculations["solution_v1.sum_solids_g"] = formatDouble(trace.sumSolidsG)
        calculations["solution_v1.sum_counted_liquids_ml"] = formatDouble(trace.sumCountedLiquidsMl)
        calculations["solution_v1.kvo_applied"] = trace.kvoApplied ? "true" : "false"
        calculations["solution_v1.kvo_contribution_ml"] = formatDouble(trace.kvoContributionMl)

        for key in trace.requiredMassesG.keys.sorted() {
            if let value = trace.requiredMassesG[key] {
                calculations["solution_v1.required_mass_g.\(key)"] = formatDouble(value)
            }
        }

        for key in trace.concentrateVolumesMl.keys.sorted() {
            if let value = trace.concentrateVolumesMl[key] {
                calculations["solution_v1.concentrate_ml.\(key)"] = formatDouble(value)
            }
        }

        return calculations
    }

    private func makeV1PpkSections(document: SolutionPPKDocument) -> [PpkSection] {
        if !document.sections.isEmpty {
            let preferredOrder = [
                "input_data", "normalization", "calculations", "technology", "validation", "dose", "packaging", "control", "packaging_storage", "technology_order", "math_justification", "technological_justification"
            ]
            let keys = document.sections.keys.sorted { lhs, rhs in
                let leftIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
                let rightIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
                if leftIndex == rightIndex {
                    return lhs < rhs
                }
                return leftIndex < rightIndex
            }
            return keys.compactMap { key in
                let rawLines = document.sections[key] ?? []
                let localizedLines = uniquePreservingOrder(
                    rawLines
                        .map { localizedPpkLine($0, sectionKey: key) }
                        .map { stripListPrefix($0) }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
                if localizedLines.isEmpty {
                    return nil
                }
                return PpkSection(title: localizedPpkSectionTitle(key), lines: localizedLines)
            }
        }

        let renderedLines = document.renderedText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !renderedLines.isEmpty else { return [] }
        let localized = uniquePreservingOrder(
            renderedLines
                .map { localizedPpkLine($0, sectionKey: "ppk_rendered") }
                .map { stripListPrefix($0) }
                .filter { !$0.isEmpty }
        )
        return [PpkSection(title: "ППК", lines: localized)]
    }

    private func localizedPpkSectionTitle(_ key: String) -> String {
        switch key {
        case "input_data": return "Исходные данные"
        case "normalization": return "Нормализация"
        case "calculations": return "Расчеты"
        case "technology": return "Технология"
        case "validation": return "Контроль и предупреждения"
        case "dose": return "Контроль доз"
        case "packaging": return "Оформление и хранение"
        case "packaging_storage": return "Упаковка и хранение"
        case "control": return "Контроль качества"
        case "technology_order": return "Порядок внесения"
        case "math_justification": return "Обоснование расчетов"
        case "technological_justification": return "Технологическое обоснование"
        default: return key
        }
    }

    private func localizedPpkLine(_ line: String, sectionKey: String) -> String {
        let value = line
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sectionKey == "technology" {
            return normalizedV1StepTitle(value)
        }

        if sectionKey == "validation" {
            if let separator = value.firstIndex(of: ":") {
                let code = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawMessage = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let localizedCode = localizedWarningCode(code)
                let localizedMessage = normalizeValidationMessage(code: code, rawMessage: rawMessage)
                return "\(localizedCode): \(localizedMessage)"
            }
        }

        if value.hasPrefix("Dosage form:") {
            return value.replacingOccurrences(of: "Dosage form:", with: "Лекарственная форма:")
        }
        if value.hasPrefix("Route:") {
            return value.replacingOccurrences(of: "Route:", with: "Путь введения:")
        }
        if value.hasPrefix("Branch:") {
            return value.replacingOccurrences(of: "Branch:", with: "Технологическая ветка:")
        }
        if value.hasPrefix("Profile.solutionType:") {
            return value.replacingOccurrences(of: "Profile.solutionType:", with: "Профиль раствора:")
        }
        if value.hasPrefix("Profile.solventType:") {
            return value.replacingOccurrences(of: "Profile.solventType:", with: "Тип растворителя:")
        }
        if value.hasPrefix("Profile.finalSystem:") {
            return value.replacingOccurrences(of: "Profile.finalSystem:", with: "Финальная система:")
        }
        if value.hasPrefix("Profile.solventCalculationMode:") {
            return value.replacingOccurrences(of: "Profile.solventCalculationMode:", with: "Режим расчета растворителя:")
        }
        if value.hasPrefix("Profile.kouBand:") {
            return value.replacingOccurrences(of: "Profile.kouBand:", with: "Диапазон КУО:")
        }
        if value.hasPrefix("Profile.automaticRule:") {
            return value.replacingOccurrences(of: "Profile.automaticRule:", with: "Автоматическое правило:")
        }
        if value.hasPrefix("sumSolidsG=") {
            return value.replacingOccurrences(of: "sumSolidsG=", with: "Сумма твердых веществ, g = ")
        }
        if value.hasPrefix("sumCountedLiquidsMl=") {
            return value.replacingOccurrences(of: "sumCountedLiquidsMl=", with: "Сумма учтенных жидкостей, ml = ")
        }
        if value.hasPrefix("waterToAddMl=") {
            return value.replacingOccurrences(of: "waterToAddMl=", with: "Вода для доведения, ml = ")
        }
        if value.hasPrefix("Solvent mode:") {
            return value.replacingOccurrences(of: "Solvent mode:", with: "Режим растворителя:")
        }
        if value.hasPrefix("KVO:") {
            return value.replacingOccurrences(of: "KVO:", with: "КУО:")
        }
        if value.hasPrefix("Water ad:") {
            return value.replacingOccurrences(of: "Water ad:", with: "Вода ad:")
        }
        if value.hasPrefix("Aqua purificata q.s. ad") {
            return value.replacingOccurrences(of: "Aqua purificata q.s. ad", with: "Aqua purificata до")
        }
        if value.hasPrefix("packaging=") {
            return value.replacingOccurrences(of: "packaging=", with: "Упаковка: ")
        }
        if value.hasPrefix("labels=") {
            return value.replacingOccurrences(of: "labels=", with: "Этикетки: ")
        }
        if value.hasPrefix("storage=") {
            return value.replacingOccurrences(of: "storage=", with: "Хранение: ")
        }

        return value
    }

    private func localizedWarningCode(_ code: String) -> String {
        switch code {
        case "solution.catalog.acidSensitive": return "Кислотная несовместимость"
        case "solution.catalog.alkaliSensitive": return "Щелочная несовместимость"
        case "solution.catalog.glycerinPhShift": return "Сдвиг pH в глицерине"
        case "solution.tweenspan.incompatibility": return "Несовместимость Tween/Span"
        case "solution.hexamine.acidicRisk": return "Риск для гексаметилентетрамина"
        case "solution.iodine.iodide.required": return "Требуется йодидный комплекс"
        case "solution.iodine.iodide.ratio": return "Недостаточное соотношение Iodidum/Iodum"
        case "unresolved_substance": return "Неопознанный ингредиент"
        case "missing_behavior_profile": return "Отсутствует поведенческий профиль"
        case "branch_not_allowed_for_substance": return "Ветка не разрешена для вещества"
        case "co_solvent_required_but_missing": return "Требуется сорастворитель"
        case "blocked_aqueous_true_solution_used": return "Блокирован водный true-solution путь"
        case "route_policy_conflict": return "Конфликт route-policy"
        case "dose_control_required_but_unresolved": return "Контроль доз не завершен"
        default:
            return code
        }
    }

    private func normalizeValidationMessage(code: String, rawMessage: String) -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message == "." {
            switch code {
            case "branch_not_allowed_for_substance":
                return "Для вещества выбранная технологическая ветка не допускается"
            case "co_solvent_required_but_missing":
                return "Требуется сорастворитель, но он не найден в составе"
            case "blocked_aqueous_true_solution_used":
                return "Простой водный путь для этого состава запрещен"
            case "route_policy_conflict":
                return "Ограничения пути введения не согласованы с выбранной веткой"
            default:
                return "Требуется проверка фармацевтом"
            }
        }
        return message
    }

    private func resolveLegacyWaterToAddMl(calculations: [String: String]) -> Double? {
        let keyPriority = [
            "primary_aqueous_to_measure_ml",
            "drops_water_to_measure_ml",
            "ophthalmic_water_to_measure_ml",
            "metrology.solution.dilution_water_ml",
            "water_to_add_ml",
            "water_to_measure_ml"
        ]

        for key in keyPriority {
            if let value = calculations[key], let parsed = parseNumeric(value) {
                return parsed
            }
        }

        let fallbackCandidates = calculations.keys
            .filter { key in
                let normalized = key.lowercased()
                return normalized.contains("water")
                    && (normalized.contains("measure") || normalized.contains("add") || normalized.contains("dilution"))
            }
            .sorted()

        for key in fallbackCandidates {
            if let value = calculations[key], let parsed = parseNumeric(value) {
                return parsed
            }
        }

        return nil
    }

    private func extractLegacyPackagingAndLabels(sections: [PpkSection]) -> (packaging: [String], labels: [String]) {
        let targetSections = sections.filter { section in
            let normalizedTitle = normalizeForCompare(section.title)
            return matchesAny(
                normalizedTitle,
                needles: ["упаков", "маркуван", "оформлен", "зберіган", "фасуван", "этикет", "етикет"]
            )
        }

        var packaging: [String] = []
        var labels: [String] = []

        for section in targetSections {
            for rawLine in section.lines {
                let line = stripListPrefix(rawLine)
                guard !line.isEmpty else { continue }
                let normalizedLine = normalizeForCompare(line)

                if matchesAny(normalizedLine, needles: ["упаков", "тара", "флакон", "контейнер", "туб", "баноч", "пакет", "капсул", "закорк"]) {
                    packaging.append(extractValueAfterColon(line) ?? line)
                }

                if matchesAny(normalizedLine, needles: ["маркуван", "етикет", "label"]) {
                    let extracted = extractQuotedChunks(line)
                    if extracted.isEmpty {
                        if let value = extractValueAfterColon(line), !value.isEmpty {
                            labels.append(value)
                        } else {
                            labels.append(line)
                        }
                    } else {
                        labels.append(contentsOf: extracted)
                    }
                }
            }
        }

        return (
            packaging: uniqueSorted(packaging),
            labels: uniqueSorted(labels)
        )
    }

    private func mapLegacyBranch(legacy: SolutionEngineLegacySnapshot) -> String? {
        let blocks = Set(legacy.activatedBlocks)
        if blocks.contains(BuretteSystemBlock.blockId) {
            return "aqueous_burette_solution"
        }

        if blocks.contains(NonAqueousSolutionsBlock.blockId) || legacy.routeBranch == "non_aqueous_solution" {
            return "non_aqueous_solution"
        }

        if blocks.contains(StandardSolutionsBlock.blockId) {
            return "standard_solution_mix"
        }

        if blocks.contains(WaterSolutionsBlock.blockId) || legacy.routeBranch == "water_solution" {
            return "aqueous_true_solution"
        }

        return nil
    }

    private func branchesCompatible(legacy: String, solutionV1: String) -> Bool {
        if legacy == solutionV1 { return true }
        if legacy == "non_aqueous_solution" && solutionV1 == "volatile_non_aqueous_solution" { return true }
        if legacy == "standard_solution_mix", ["standard_solution_mix", "ready_solution_mix"].contains(solutionV1) { return true }
        return false
    }

    private func makeSolutionRequest(draft: ExtempRecipeDraft, facts: RxFacts) -> SolutionEngineRequest {
        let ingredients = draft.ingredients.map { ingredient in
            let name = preferredIngredientName(ingredient)
            let isAd = ingredient.isAd || ingredient.isQS
            let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let massG = unit == "g" || unit == "г" ? ingredient.amountValue : nil
            let volumeMl = unit == "ml" || unit == "мл" ? ingredient.amountValue : nil
            let concentrationPercent = draft.solutionDisplayPercent(for: ingredient)

            let adTarget: Double? = {
                guard isAd else { return nil }
                if let volumeMl, volumeMl > 0 { return volumeMl }
                return draft.explicitLiquidTargetMl ?? draft.legacyAdOrQsLiquidTargetMl
            }()

            return StructuredIngredientInput(
                name: name,
                presentationKind: mapPresentationKind(ingredient),
                massG: massG,
                volumeMl: volumeMl,
                concentrationPercent: concentrationPercent,
                ratio: cleaned(ingredient.refHerbalRatio),
                isAd: isAd,
                adTargetMl: adTarget
            )
        }

        let structured = StructuredSolutionInput(
            dosageForm: "solution",
            route: inferSolutionRoute(draft: draft, facts: facts),
            targetVolumeMl: draft.explicitLiquidTargetMl ?? draft.legacyAdOrQsLiquidTargetMl ?? facts.inferredLiquidTargetMl,
            signa: draft.signa,
            ingredients: ingredients
        )

        let forcedConcentrates: [String: String]? = {
            guard draft.useBuretteSystem else { return nil }
            let burette = BuretteSystem.evaluateBurette(draft: draft)
            guard !burette.items.isEmpty else { return nil }
            guard !burette.issues.contains(where: { $0.severity == .blocking }) else { return nil }

            var map: [String: String] = [:]
            for ingredient in draft.ingredients where burette.matchedIngredientIds.contains(ingredient.id) {
                let key = preferredIngredientName(ingredient)
                if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    map[key] = "burette_forced"
                }
            }
            return map.isEmpty ? nil : map
        }()

        return SolutionEngineRequest(
            recipeText: nil,
            route: structured.route,
            structuredInput: structured,
            forceReferenceConcentrate: forcedConcentrates
        )
    }

    private func mapPresentationKind(_ ingredient: IngredientDraft) -> String? {
        let refType = ingredient.refNormalizedType

        if ingredient.presentationKind == .standardSolution || refType == "standardsolution" || refType == "liquidstandard" || refType == "buffersolution" {
            return "standardSolution"
        }

        if refType == "tincture" {
            return "tincture"
        }

        if refType == "extract" {
            let extractType = cleaned(ingredient.refExtractType)?.lowercased() ?? ""
            if extractType.contains("sicc") || extractType.contains("dry") {
                return "dry_extract"
            }
            return "liquid_extract"
        }

        if refType == "syrup" {
            return "syrup"
        }

        if refType == "solvent",
           let solvent = NonAqueousSolventCatalog.classify(ingredient: ingredient) {
            switch solvent {
            case .ethanol:
                return "alcohol"
            case .glycerin:
                return "glycerin"
            case .fattyOil, .mineralOil, .vinylin, .viscousOther:
                return "oil"
            case .ether, .chloroform, .volatileOther:
                return "volatile_solvent"
            }
        }

        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) || ingredient.isReferenceAromaticWater {
            return "aqueous"
        }

        if ingredient.presentationKind == .solution {
            return "solution"
        }

        return "solid"
    }

    private func preferredIngredientName(_ ingredient: IngredientDraft) -> String {
        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
            return "Aqua purificata"
        }
        let latinNom = cleaned(ingredient.refNameLatNom)
        let latinGen = cleaned(ingredient.refNameLatGen)
        let inn = cleaned(ingredient.refInnKey)
        let display = cleaned(ingredient.displayName)
        return latinNom ?? latinGen ?? inn ?? display ?? "Substantia"
    }

    private func inferSolutionRoute(draft: ExtempRecipeDraft, facts: RxFacts) -> String {
        let semantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        let signa = semantics.normalizedSigna

        if draft.isOphthalmicDrops || semantics.isEyeRoute || facts.isOphthalmic {
            return "ophthalmic"
        }
        if semantics.isNasalRoute {
            return "nasal"
        }
        if containsAny(signa, needles: ["уш", "вух", "otic", "ear"]) {
            return "otic"
        }
        if containsAny(signa, needles: ["ингал", "інгал", "inhal"]) {
            return "inhalation"
        }
        if containsAny(signa, needles: ["ін'єк", "инъек", "inject", "parenter"]) {
            return "injection"
        }
        if semantics.isExternalRoute {
            return "external"
        }
        return "oral"
    }

    private func containsAny(_ text: String, needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseNumeric(_ value: String) -> Double? {
        let pattern = #"-?\d+(?:[.,]\d+)?"#
        guard let match = value.range(of: pattern, options: .regularExpression) else { return nil }
        let token = value[match].replacingOccurrences(of: ",", with: ".")
        return Double(token)
    }

    private func parseBoolean(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    private func computeSolidsPercent(from request: SolutionEngineRequest) -> Double? {
        guard let structured = request.structuredInput,
              let target = structured.targetVolumeMl,
              target > 0 else {
            return nil
        }

        let solidsMass = structured.ingredients.reduce(0.0) { partial, ingredient in
            let mass = ingredient.massG ?? 0
            if ingredient.isAd == true {
                return partial
            }
            return partial + max(0, mass)
        }
        return solidsMass / target * 100
    }

    private func inferLegacyKuoUsage(context: RxPipelineContext, solidsPercent: Double?) -> Bool? {
        if let ignored = parseBoolean(context.calculations["ignore_kuo_for_burette"]), ignored {
            return false
        }

        let explicitKuoKeys = context.calculations.keys.filter { key in
            let normalized = key.lowercased()
            return (normalized.contains("kuo") || normalized.contains("kvo")) && !normalized.contains("ignore")
        }
        if !explicitKuoKeys.isEmpty {
            return true
        }

        if let solidsPercent {
            return solidsPercent >= 3
        }

        return nil
    }

    private func inferLegacyFinalAdjustment(context: RxPipelineContext) -> Bool {
        if context.techPlan.steps.contains(where: { $0.kind == .bringToVolume }) {
            return true
        }
        return context.techPlan.steps.contains { step in
            let normalized = normalizeForCompare(step.title)
            return matchesAny(normalized, needles: ["довед", "до обем", "до объем", "ad ", "bring to volume"])
        }
    }

    private func optionalDoublesEqual(_ lhs: Double?, _ rhs: Double?, tolerance: Double) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left - right) <= tolerance
        default:
            return false
        }
    }

    private func normalizeForCompare(_ value: String) -> String {
        let lowercased = value.lowercased()
        let withoutPunctuation = lowercased.replacingOccurrences(
            of: #"[^a-zа-яіїєґ0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return withoutPunctuation
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func normalizeStringSet(_ values: [String]) -> [String] {
        uniqueSorted(
            values
                .map { normalizeForCompare(stripListPrefix($0)) }
                .filter { !$0.isEmpty }
        )
    }

    private func stripListPrefix(_ value: String) -> String {
        var current = value
        while true {
            let cleanedValue = current.replacingOccurrences(
                of: #"^\s*(?:[•\-\*]+\s*|\d+[\.\)]\s*)"#,
                with: "",
                options: .regularExpression
            )
            if cleanedValue == current {
                break
            }
            current = cleanedValue
        }
        return current.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractValueAfterColon(_ line: String) -> String? {
        guard let separatorIndex = line.firstIndex(of: ":") else { return nil }
        let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func extractQuotedChunks(_ line: String) -> [String] {
        let pattern = #"«([^»]+)»"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        let chunks = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            let value = nsLine.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return uniqueSorted(chunks)
    }

    private func matchesAny(_ value: String, needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func normalizedConfidence(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized == "approximate" || normalized == "heuristic" {
            return "heuristic"
        }
        return normalized
    }

    private func debugList(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[\(values.joined(separator: ", "))]"
    }

    private func debugOptionalDouble(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.3f", value)
    }

    private func debugRoleMap(_ roles: [String: String]) -> String {
        let pairs = roles.keys.sorted().map { key in
            "\(key)=\(roles[key] ?? "unknown")"
        }
        return debugList(pairs)
    }

    private func formatDouble(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func jsonString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func referenceDebugLog(_ message: String) {
#if DEBUG
        print("[ModularRxEngine] \(message)")
#endif
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private static func makeReasoningEngine() -> RxReasoningEngine {
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL {
            let bundleCandidates = [
                resourceURL.appendingPathComponent("URAN_Pharma_Engine"),
                resourceURL.appendingPathComponent("Uran/URAN_Pharma_Engine")
            ]
            for candidate in bundleCandidates {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    do {
                        let references = try SolutionReferenceStore(baseURL: candidate)
                        referenceDebugLog("ReasoningEngine loaded references from bundle path: \(references.baseURL.standardizedFileURL.path)")
                        return RxReasoningEngine.makeDefault(references: references)
                    } catch {
                        referenceDebugLog("ReasoningEngine failed loading bundle path \(candidate.standardizedFileURL.path): \(error)")
                    }
                }
            }
        }

        do {
            let references = try SolutionReferenceStore()
            referenceDebugLog("ReasoningEngine loaded references from fallback path: \(references.baseURL.standardizedFileURL.path)")
            return RxReasoningEngine.makeDefault(references: references)
        } catch {
            referenceDebugLog("ReasoningEngine fallback load failed: \(error)")
        }
        referenceDebugLog("ReasoningEngine initialized without external references")
        return RxReasoningEngine.makeDefault()
    }

    private static func makeSolutionEngine() -> SolutionEngine? {
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL {
            let bundleCandidates = [
                resourceURL.appendingPathComponent("URAN_Pharma_Engine"),
                resourceURL.appendingPathComponent("Uran/URAN_Pharma_Engine")
            ]
            for candidate in bundleCandidates {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    do {
                        let references = try SolutionReferenceStore(baseURL: candidate)
                        let engine = try SolutionEngine(references: references)
                        referenceDebugLog("SolutionEngine loaded references from bundle path: \(references.baseURL.standardizedFileURL.path)")
                        return engine
                    } catch {
                        referenceDebugLog("SolutionEngine failed loading bundle path \(candidate.standardizedFileURL.path): \(error)")
                    }
                }
            }
        }

        do {
            let references = try SolutionReferenceStore()
            let engine = try SolutionEngine(references: references)
            referenceDebugLog("SolutionEngine loaded references from fallback path: \(references.baseURL.standardizedFileURL.path)")
            return engine
        } catch {
            referenceDebugLog("SolutionEngine fallback load failed: \(error)")
            return nil
        }
    }
}
