# Solution Engine Public API (v1)

## Основная точка входа
- Тип: `SolutionEngine`
- Функции:
  - `init(references: SolutionReferenceStore? = nil) throws`
  - `process(request: SolutionEngineRequest) -> SolutionEngineResult`

## Dependency Injection / References
- Тип: `SolutionReferenceStore`
- Функции:
  - `init(baseURL: URL? = nil) throws`
  - `resolveSubstanceKey(for name: String) -> String?`
  - `resolveBehavior(for normalizedName: String, substanceKey: String?) -> IngredientBehaviorRecord?`
  - `resolveSolubility(for normalizedName: String, substanceKey: String?) -> SolubilityRuleRecord?`
  - `resolveConcentrate(for normalizedName: String, substanceKey: String?) -> ConcentrateReferenceRecord?`
  - `resolveSpecialCase(for normalizedName: String, substanceKey: String?) -> SpecialDissolutionCaseRecord?`
  - `resolvePackaging(for normalizedName: String, substanceKey: String?) -> StabilityPackagingRecord?`
  - `resolveSpecSubstanceKey(for normalizedName: String, substanceKey: String?) -> String?`
  - `resolveSpecCanonicalName(for normalizedName: String, substanceKey: String?) -> String?`
  - `resolveRoutePolicy(for routeCandidate: String) -> RoutePolicyRecord?`
  - `static normalizeToken(_ token: String) -> String`

## Входной контракт
- `SolutionEngineRequest`
  - `recipeText: String?`
  - `route: String?`
  - `structuredInput: StructuredSolutionInput?`
  - `forceReferenceConcentrate: [String: String]?`
  - `init(recipeText:route:structuredInput:forceReferenceConcentrate:)`
- `StructuredSolutionInput`
  - `dosageForm`, `route`, `targetVolumeMl`, `signa`, `ingredients`
- `StructuredIngredientInput`
  - `name`, `presentationKind`, `massG`, `volumeMl`, `concentrationPercent`, `ratio`, `isAd`, `adTargetMl`

## Выходной контракт
- `SolutionEngineResult`
  - `classification`, `solutionBranch`, `route`
  - `solutionProfile` (включая `solventCalculationMode`: `qs_to_volume | kou_calculation | dilution | pharmacopoeial | non_aqueous`)
  - `normalizedIngredients`
  - `calculationTrace`
  - `technologySteps`, `technologyFlags`
  - `validationReport`, `warnings`
  - `doseControl`
  - `packaging`
  - `ppkDocument`
  - `confidence`, `debugTrace`, `state`

## Сопутствующие API-типы состояния и диагностики
- `SolutionEngineState`
- `SolutionEngineConfidence`
- `SolutionWarningSeverity`
- `SolutionWarning`
- `SolutionCalculationTrace`
- `SolutionDoseControl`
- `SolutionPackaging`
- `SolutionPPKDocument`
- `SolutionClassificationProfile`
- `SolutionNormalizedIngredient`

## Внутренние (не использовать как внешний API)
- `SolutionParsedInput`, `SolutionParsedIngredient`
- `SolutionResolvedIngredient`, `SolutionBehaviorIngredient`
- `SolutionRouteResolution`, `SolutionBranchResolution`
- `SolutionEngineContext`
- Модульные типы-исполнители:
  `IngredientParser`, `SubstanceResolver`, `BehaviorProfileResolver`,
  `SolutionBranchSelector`, `SolutionCalculationEngine`, `TechnologyPlanner`,
  `ValidationEngine`, `DoseValidator`, `PackagingResolver`, `PPKRenderer`
