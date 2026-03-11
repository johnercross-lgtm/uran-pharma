# PHARM_ENGINE_STATE_MACHINE.md

Version: 1.0
Purpose: deterministic state machine for the pharmaceutical compounding engine in URAN Pharma.
Goal: force the engine to move step by step through parsing, normalization, classification, calculation, validation, and rendering without skipping or inventing logic.

---

## 0. Core principle

The engine must not calculate anything until the input has passed through the required prior states.

The engine must not:
- render PPC before validation,
- validate dose before substance resolution,
- apply KVO before solution branch selection,
- choose packaging before route and stability analysis.

Every formulation must move through explicit states.

---

## 1. State overview

```text
S0  INPUT_RECEIVED
S1  INPUT_PARSED
S2  INGREDIENTS_NORMALIZED
S3  SUBSTANCES_RESOLVED
S4  BEHAVIOR_PROFILES_ATTACHED
S5  ROUTE_RESOLVED
S6  FORM_CLASSIFIED
S7  SOLUTION_BRANCH_SELECTED
S8  PRECALC_CHECKS_DONE
S9  CORE_CALCULATIONS_DONE
S10 TECHNOLOGY_PLAN_BUILT
S11 VALIDATION_DONE
S12 DOSE_CONTROL_DONE
S13 PACKAGING_AND_STORAGE_DONE
S14 PPC_RENDERED
S15 FINAL_RESULT_EMITTED

SX  BLOCKED
SW  PARTIAL_WITH_WARNINGS
Да. Это очень полезная штука.
`PHARM_ENGINE_STATE_MACHINE.md` нужен, чтобы Codex не прыгал хаотично между парсингом, расчётом и рендером, а шёл **по жёстким состояниям**.

Ниже даю готовый файл.

# `PHARM_ENGINE_STATE_MACHINE.md`

````md
# PHARM_ENGINE_STATE_MACHINE.md

Version: 1.0
Purpose: deterministic state machine for the pharmaceutical compounding engine in URAN Pharma.
Goal: force the engine to move step by step through parsing, normalization, classification, calculation, validation, and rendering without skipping or inventing logic.

---

## 0. Core principle

The engine must not calculate anything until the input has passed through the required prior states.

The engine must not:
- render PPC before validation,
- validate dose before substance resolution,
- apply KVO before solution branch selection,
- choose packaging before route and stability analysis.

Every formulation must move through explicit states.

---

## 1. State overview

```text
S0  INPUT_RECEIVED
S1  INPUT_PARSED
S2  INGREDIENTS_NORMALIZED
S3  SUBSTANCES_RESOLVED
S4  BEHAVIOR_PROFILES_ATTACHED
S5  ROUTE_RESOLVED
S6  FORM_CLASSIFIED
S7  SOLUTION_BRANCH_SELECTED
S8  PRECALC_CHECKS_DONE
S9  CORE_CALCULATIONS_DONE
S10 TECHNOLOGY_PLAN_BUILT
S11 VALIDATION_DONE
S12 DOSE_CONTROL_DONE
S13 PACKAGING_AND_STORAGE_DONE
S14 PPC_RENDERED
S15 FINAL_RESULT_EMITTED

SX  BLOCKED
SW  PARTIAL_WITH_WARNINGS
````

---

## 2. State descriptions

### S0 — INPUT_RECEIVED

Entry state.

Input may be:

* free-text prescription
* structured ingredient list
* hybrid parser output

Required data captured:

* raw text
* metadata
* language context
* optional signa
* optional route
* optional target volume

Transition:

* to `S1`

---

### S1 — INPUT_PARSED

The parser extracts:

* dosage form
* ingredient tokens
* amounts
* units
* concentrations
* ad/q.s. markers
* route hints
* signa
* known abbreviations

Output:

* parsed ingredient list
* parser warnings

Transition:

* if zero usable ingredients -> `SX`
* otherwise -> `S2`

---

### S2 — INGREDIENTS_NORMALIZED

Normalize:

* units
* decimal separators
* Latin abbreviations
* route strings
* concentration syntax
* ratio syntax
* ad markers

Output:

* normalized ingredient records

Transition:

* to `S3`

---

### S3 — SUBSTANCES_RESOLVED

Resolve every ingredient through:

* `SUBSTANCE_ALIAS_TABLE.json`
* `substances_master.json`

Attach:

* `substanceKey`
* canonical names
* safety flags
* classification
* physical state

Rules:

* unresolved ingredient must produce warning
* unresolved ingredient must not silently inherit another identity

Transition:

* if critical substances unresolved and calculation depends on them -> `SW` or `SX`
* otherwise -> `S4`

---

### S4 — BEHAVIOR_PROFILES_ATTACHED

Attach behavior profile to each ingredient using:

* ingredient behavior rules
* ingredient behavior tables
* concentrate reference
* solution reference
* solubility rules
* special dissolution cases

Each ingredient must get:

* countsAsLiquid
* countsAsSolid
* affectsAd
* affectsKvo
* requiresSeparateDissolution
* addAtEnd
* heatPolicy
* volatilityPolicy
* filtrationPolicy
* phaseType

Transition:

* if required behavior missing -> warning and continue to `S5`
* if behavior conflict critical -> `SX`
* else -> `S5`

---

### S5 — ROUTE_RESOLVED

Resolve route from:

1. explicit route input
2. dosage-form context
3. signa hints
4. safe fallback only if allowed

Apply:

* `ROUTE_POLICY_TABLE_SOLUTIONS.json`

Output:

* resolved route
* route warnings
* route restrictions

Transition:

* if strict route unsupported -> `SW` or `SX`
* else -> `S6`

---

### S6 — FORM_CLASSIFIED

Classify dosage form:

* solution
* powder
* ointment
* drops
* etc.

Current focus:

* solutions

If solution:
classify preliminary family:

* aqueous candidate
* concentrate candidate
* standard-solution candidate
* non-aqueous candidate
* special-route candidate

Transition:

* if not solution and current engine only supports solutions -> `SW` or exit to another module
* else -> `S7`

---

### S7 — SOLUTION_BRANCH_SELECTED

Select exact solution branch.

Possible branches:

* aqueous_true_solution
* aqueous_burette_solution
* standard_solution_mix
* ready_solution_mix
* mixed_solution_path
* non_aqueous_solution
* volatile_non_aqueous_solution
* special_dissolution_path
* special_route_reference_required

Selection is based on:

* behavior profiles
* solubility rules
* route policy
* concentrate table
* special dissolution cases

Rules:

* do not use generic aqueous path if blocked by solubility gate
* do not use burette path without concentrate support
* do not use ophthalmic ordinary path without route support

Transition:

* if branch unresolved -> `SW`
* else -> `S8`

---

### S8 — PRECALC_CHECKS_DONE

Run pre-calculation checks before math.

Checks:

* target volume available?
* ad conflict?
* multiple ad?
* fixed water vs ad?
* phase compatibility?
* required co-solvent present?
* separate dissolution stage required?
* strict route unsupported?
* ready solution accidentally in solids?

No final calculations allowed before this state passes.

Transition:

* if critical conflict -> `SX`
* else -> `S9`

---

### S9 — CORE_CALCULATIONS_DONE

Perform mathematics according to selected branch.

Possible calculations:

* required mass from target concentration
* concentrate volume from mass
* sum of counted liquids
* KVO contribution
* ad solvent amount
* density-aware conversion
* dose-per-container basis for homogeneous oral solutions

Rules:

* KVO only on valid dry branch
* concentrate counts as liquid
* standard solution counts as liquid
* ready solution counts as liquid
* ad must show formula trace

Output:

* structured calculation steps
* exact / approximate / heuristic flags

Transition:

* to `S10`

---

### S10 — TECHNOLOGY_PLAN_BUILT

Construct technology steps from:

* branch type
* behavior profiles
* special dissolution cases
* heat/volatility restrictions
* late-addition requirements

Examples:

* dissolve separately then combine
* measure concentrates then water ad
* do not heat
* add tincture last
* avoid unnecessary filtration

Rules:

* technology must come from behavior/state, not from random templates
* no default filtration where restricted
* no heating where forbidden

Transition:

* to `S11`

---

### S11 — VALIDATION_DONE

Run full validation using:

* validation conflict rules
* route restrictions
* solution branch restrictions
* rendering restrictions

Validation categories:

* ingredient identity
* branch compatibility
* KVO misuse
* ad misuse
* phase incompatibility
* technology conflict
* packaging conflict
* PPC phrase conflict

Output:

* structured warnings
* critical conflicts
* confidence downgrade if needed

Transition:

* if blocked -> `SX`
* else -> `S12`

---

### S12 — DOSE_CONTROL_DONE

Only after substance resolution and core calculation.

Apply if:

* route requires it
* substance safety requires it
* signa parse is possible

Use:

* `dose_limits.json`
* shared signa parser

Outputs:

* single dose
* daily dose
* dose warnings
* unresolved signa warning if needed

Transition:

* to `S13`

---

### S13 — PACKAGING_AND_STORAGE_DONE

Determine final:

* bottle type
* dark glass / clear glass
* tight closure
* cool storage
* labels
* shake or no shake

Use:

* route policy
* stability and packaging table
* validation corrections

Rule:
the strictest required packaging/storage wins.

Transition:

* to `S14`

---

### S14 — PPC_RENDERED

Generate final PPC using:

* calculation trace
* technology plan
* validation results
* packaging results
* phrase rules

Rules:

* no duplicate sections
* no stock concentrate QC text in final mixture PPC
* no shake label for true solution unless justified
* final object naming must be consistent

Transition:

* to `S15`

---

### S15 — FINAL_RESULT_EMITTED

Return final structured result:

* classification
* branch
* normalized ingredients
* calculations
* technology steps
* dose control
* packaging
* warnings
* PPC text
* confidence

Final status may be:

* exact
* approximate
* heuristic
* blocked

---

## 3. Error / partial states

### SX — BLOCKED

Use when safe deterministic output is impossible.

Examples:

* impossible formulation
* critical route conflict
* sterility-required unsupported path
* multiple ad without resolution
* missing target volume in required ad path

Return:

* blocked status
* why blocked
* what is still known safely

### SW — PARTIAL_WITH_WARNINGS

Use when part of the result is safe, but full confidence is impossible.

Examples:

* target inferred by fallback
* unresolved ingredient behavior profile
* route partially unsupported
* signa unresolved for dose control
* missing reference for a special case

Return:

* partial result
* warnings
* downgraded confidence

---

## 4. Allowed transitions

```text
S0  -> S1
S1  -> S2 | SX
S2  -> S3
S3  -> S4 | SW | SX
S4  -> S5 | SX
S5  -> S6 | SW | SX
S6  -> S7 | SW
S7  -> S8 | SW
S8  -> S9 | SX
S9  -> S10
S10 -> S11
S11 -> S12 | SX
S12 -> S13
S13 -> S14
S14 -> S15
```

No backward silent jumps allowed.
If recalculation is needed, it must explicitly restart from the affected prior state.

---

## 5. Re-entry rules

If a critical change happens, restart from the earliest affected state.

Examples:

* ingredient alias corrected -> restart from `S3`
* route changed -> restart from `S5`
* branch changed -> restart from `S7`
* ad target changed -> restart from `S8`
* signa updated -> restart from `S12`

Do not patch final PPC directly without recomputing affected states.

---

## 6. Confidence policy by state machine

### exact

Allowed only if:

* no critical conflicts
* no unresolved rule
* no fallback target inference
* branch selected deterministically

### approximate

Allowed if:

* no critical conflicts
* some warning-level uncertainty exists
* calculations are still materially valid

### heuristic

Allowed if:

* fallback inference was used
* branch or target chosen conservatively
* result is useful but not strict

### blocked

Used if:

* safe deterministic completion is impossible

---

## 7. Mandatory guardrails

### GUARD_001

Do not perform KVO before `S7`.

### GUARD_002

Do not compute dose before `S9`.

### GUARD_003

Do not render PPC before `S11`.

### GUARD_004

Do not assign packaging before `S13`.

### GUARD_005

Do not choose special dissolution template before `S4`.

### GUARD_006

Do not use route-specific phrases before `S5`.

### GUARD_007

Do not call a result exact if `SW` occurred.

---

## 8. Minimum debug trace

The engine should be able to output a debug trace like:

```text
S0 INPUT_RECEIVED
S1 INPUT_PARSED
S2 INGREDIENTS_NORMALIZED
S3 SUBSTANCES_RESOLVED
S4 BEHAVIOR_PROFILES_ATTACHED
S5 ROUTE_RESOLVED
S6 FORM_CLASSIFIED
S7 SOLUTION_BRANCH_SELECTED = aqueous_burette_solution
S8 PRECALC_CHECKS_DONE
S9 CORE_CALCULATIONS_DONE
S10 TECHNOLOGY_PLAN_BUILT
S11 VALIDATION_DONE
S12 DOSE_CONTROL_DONE
S13 PACKAGING_AND_STORAGE_DONE
S14 PPC_RENDERED
S15 FINAL_RESULT_EMITTED (exact)
```

This trace is extremely useful for debugging recipe-breaker cases.

---

## 9. Recommended implementation objects

Suggested internal objects:

* `EngineState`
* `EngineContext`
* `ParsedInput`
* `NormalizedIngredient`
* `BehaviorProfile`
* `RouteContext`
* `SolutionBranchContext`
* `CalculationTrace`
* `ValidationReport`
* `DoseControlReport`
* `PackagingReport`
* `PPCDocument`

---

## 10. Final principle

The pharmaceutical engine must behave like a deterministic processor, not like a conversational guesser.

State machine order is mandatory.

No final pharmaceutical statement should be emitted unless the formulation has passed through all required states.

````

Как это использовать с Codex:

Дай ему архив + `CODEX_MASTER_PROMPT.md` + этот файл и скажи так:

```text
Use PHARM_ENGINE_STATE_MACHINE.md as mandatory execution order.
Do not skip states.
Do not merge states.
Do not render final PPC or exact conclusions unless the formulation has passed through all required states.
Implement the solutions module first.
````


