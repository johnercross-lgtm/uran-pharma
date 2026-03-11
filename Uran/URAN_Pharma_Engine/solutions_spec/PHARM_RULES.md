Начинай именно с этих 4.
1) PHARM_RULES.md
# PHARM_RULES.md

Version: 1.0
Purpose: deterministic rule base for the pharmaceutical compounding engine used in URAN Pharma.
Scope: extemporaneous formulations with emphasis on solutions, powders, drops, ointments, triturations, poisonous/potent substances, dose control, packaging, labeling, and PPC generation.

---

## 0. Core principles

### RULE_CORE_001 — Deterministic priority
The engine must prefer explicit pharmaceutical rules over heuristics.

Priority order:
1. Explicit structured recipe data
2. Pharmacopoeial / formal technology rules
3. Structured curated reference tables
4. Conservative heuristics with warning

If conflict exists, the engine must:
- preserve the calculation result,
- attach a warning,
- mark the decision source.

### RULE_CORE_002 — No invention of pharmaceutical rules
If a rule is missing, the engine must not fabricate technology.
It must:
- mark the case as `unresolved_rule`,
- produce a warning,
- still compute only the safe deterministic subset.

### RULE_CORE_003 — Explainability required
Every calculation block must be explainable.
The engine must be able to produce:
- formula used,
- source data,
- substitution of values,
- final result,
- assumptions.

### RULE_CORE_004 — Separation of concerns
The engine must separate:
- parsing,
- normalization,
- rule application,
- calculations,
- validation,
- PPC rendering.

### RULE_CORE_005 — Pharmaceutical conservatism
When several interpretations are possible, choose the interpretation that:
- minimizes hidden assumptions,
- avoids overdose risk,
- avoids illegal technological shortcuts,
- surfaces ambiguity.

### RULE_CORE_006 — Unit normalization
The engine must normalize masses, volumes, concentrations, ratios, and dosage expressions into canonical units before calculations.

Canonical internal units:
- mass: g
- volume: ml
- concentration percent: g / 100 ml of final solution unless explicitly declared otherwise
- drops: count and approximate ml only when calibrated drop factor is explicitly known

### RULE_CORE_007 — Rule trace
Each final block must preserve machine-readable trace:
- `rule_id`
- `source_type`
- `confidence`
- `assumption_used`

### RULE_CORE_008 — Heuristic confidence
If a heuristic is used, it must be marked as one of:
- `exact`
- `approximate`
- `heuristic`

---

## 1. Ingredient normalization

### RULE_ING_001 — Ingredient role classification
Each ingredient must be classified into one of the roles:
- activeSubstance
- solvent
- finishedSolution
- standardSolution
- concentrate
- aromaticWater
- tincture
- extractLiquid
- syrup
- nonAqueousSolvent
- ointmentBase
- triturate
- filler
- preservative
- undefined

### RULE_ING_002 — Solution-kind ingredients are liquids
If `presentationKind == solution`, ingredient is liquid.
It must not be included in `solidComponents`.

### RULE_ING_003 — Standard-solution ingredients are liquids
If `presentationKind == standardSolution`, ingredient is liquid.
It must not be included in `solidComponents`.

### RULE_ING_004 — Concentrates are liquids
If ingredient is introduced as a pharmacy concentrate / burette stock solution, it is treated as liquid for volume accounting and excluded from solid mass calculations.

### RULE_ING_005 — Dry substance path
If ingredient is a dry substance with mass and no explicit finished-solution role, it is treated as a solid substance requiring dissolution, dispersion, mixing, or levigation depending on dosage form.

### RULE_ING_006 — Ambiguous ingredient form
If the name suggests a solution, but structured fields suggest a dry substance or vice versa, the engine must raise `ingredient_form_conflict` warning.

### RULE_ING_007 — ad/q.s. classification
An ingredient marked `ad`, `ad volume`, `q.s.`, or equivalent is not treated as an ordinary quantified ingredient.
It defines final adjustment logic.

### RULE_ING_008 — Solvent phase tagging
Every liquid ingredient must be tagged as one phase:
- aqueous
- hydroalcoholic
- alcoholic
- glycerinic
- oily
- volatileOrganic
- mixed
- unknown

---

## 2. Concentration and ratio normalization

### RULE_CONC_001 — Percent solution interpretation
For solution calculations, `%` is interpreted as grams of substance per 100 ml of final solution unless explicit alternative concentration type is declared.

### RULE_CONC_002 — Ratio solution interpretation
A ratio `1:n` for standard pharmacy concentrate is interpreted as:
- 1 g substance in n ml solution
- therefore `V = m × n`
when used for concentrate volume calculation.

### RULE_CONC_003 — Decimal concentration formula
For concentrate with concentration `C_decimal`, volume is:
`V_conc = m / C_decimal`

Example:
10% -> 0.1 g/ml

### RULE_CONC_004 — Percent to required mass
For target solution `%` and final volume `V_total`:
`m_required = C_percent × V_total / 100`

### RULE_CONC_005 — Explicit target concentration priority
If recipe explicitly states target concentration and target total volume for a component, these define the required mass / equivalent concentrate volume.

### RULE_CONC_006 — Mixed concentration notations
If both `%` and `1:n` are available for the same reference solution, engine may use either but must preserve consistent explanation.

---

## 3. Total volume and ad logic

### RULE_AD_001 — Meaning of ad
`ad` means bring the preparation to the final target mass/volume after all counted ingredients are included.

### RULE_AD_002 — Final target priority
Target final volume is determined by priority:
1. explicit ingredient marked `ad`
2. explicit formulation `targetValue/targetUnit`
3. declared dosage-form total volume
4. unresolved warning if none exists

### RULE_AD_003 — Water ad formula for liquid systems
If final volume is adjusted with purified water:
`V_water = V_target - ΣV_other_liquids - ΣV_displacement_adjustments`

Only counted liquid components and explicit displacement corrections may be subtracted.

### RULE_AD_004 — ad must not be guessed from largest liquid alone
Largest-liquid fallback may be used only as a last resort and must raise warning `target_inferred_by_fallback`.

### RULE_AD_005 — Multiple ad markers conflict
If more than one component defines `ad`, engine must raise `multiple_ad_conflict`.

### RULE_AD_006 — Fixed water + ad conflict
If recipe includes explicit fixed water volume and also `ad` water for the same target without a clear two-stage meaning, engine must raise `fixed_water_vs_ad_conflict`.

### RULE_AD_007 — ad calculation explainability
Any `ad` result must show:
- target final volume,
- sum of counted liquids,
- displacement corrections,
- computed solvent to add.

---

## 4. Aqueous solutions

### RULE_SOL_AQ_001 — True aqueous solution path
If dosage form is solution and all active substances are soluble in water or are introduced as finished concentrates/solutions, classify as true aqueous solution unless contradictory evidence exists.

### RULE_SOL_AQ_002 — Finished solution is not a solid
Finished aqueous solutions must not enter:
- `Σ solids`
- solid percentage branch
- dry-substance KVO branch

### RULE_SOL_AQ_003 — Dry solute mass percentage branch
For dry substances introduced directly, calculate solid mass percentage:
`solid_percent = Σm_solids / V_target × 100`

This branch is used only for true dry solids, not for ready solutions.

### RULE_SOL_AQ_004 — KVO threshold branch
If aqueous solution is prepared from dry solids and the relevant technological threshold is reached, KVO may be applied according to reference rules.
The threshold logic must be explicit and configurable, not inferred ad hoc.

### RULE_SOL_AQ_005 — No KVO for burette concentrate method
If all active substances are introduced via ready concentrates / stock solutions in a burette method, KVO of dry substances is not applied.

### RULE_SOL_AQ_006 — Concentrate volume sum
For burette method:
`ΣV_concentrates = Σ(volume of each selected concentrate)`

Then solvent is calculated by ad formula.

### RULE_SOL_AQ_007 — Technology order for burette solution
Default order:
1. verify composition
2. select appropriate concentrates
3. measure concentrates
4. add solvent to target volume
5. mix
6. filter only if indicated
7. package
8. label

### RULE_SOL_AQ_008 — Filtration for true solution
Filtration is not added by default to a true solution prepared from clear concentrates unless:
- visible particles are possible
- prescribed by technology rule
- solution was prepared from solids and requires clarification

### RULE_SOL_AQ_009 — Shake label not default
Do not assign `shake before use` to a true homogeneous aqueous solution unless there is a specific reason:
- opalescence
- emulsion/suspension features
- unstable aromatic/volatile inclusions
- partial miscibility issue

### RULE_SOL_AQ_010 — Light-sensitive packaging
Dark glass packaging is recommended only when ingredient stability data indicates light sensitivity.
Do not generalize this to all aqueous solutions.

### RULE_SOL_AQ_011 — Meniscus rule for burette measurement
For colorless solutions read by lower meniscus.
For colored solutions read by upper meniscus.
This is auxiliary operational guidance, not a composition calculation.

### RULE_SOL_AQ_012 — Burette drain rule
Do not measure by arbitrary mark-to-mark transfer.
Measurement must be performed from zero or fixed calibrated point to full drain completion according to burette handling protocol.

### RULE_SOL_AQ_013 — Drain delay rule
After visible stream stops, hold briefly to allow final drop completion if this is part of the selected operational protocol.

### RULE_SOL_AQ_014 — Non-concentrate dry preparation order
If aqueous solution is prepared from dry substances:
1. measure part of solvent
2. dissolve substances in suitable order
3. account for KVO if required
4. bring to final volume
5. mix
6. filter only if indicated
7. package

---

## 5. Standard pharmacopoeial solutions

### RULE_STD_001 — Standard solution role
A standard pharmacopoeial solution must be treated as a predefined solution object with reference concentration and usage rules.

### RULE_STD_002 — Standard solution not recalculated as dry substance
If a standard solution is explicitly selected as ingredient, do not additionally recalculate it as if it were a dry solid unless recipe explicitly demands preparation from raw substance.

### RULE_STD_003 — Special-case activation must be explicit
Special named methods must be activated only by explicit structured marker or strong textual condition. A name mention alone is insufficient.

### RULE_STD_004 — Demyanovich special case
The Demyanovich special branch may be activated only if:
- explicit special-case field is `.demyanovich2`
- or text clearly indicates method No. 2 in addition to the name

Otherwise keep normal standard-solution handling.

---

## 6. Non-aqueous solutions

### RULE_SOL_NONAQ_001 — Non-aqueous classification
If primary solvent is alcohol, glycerin, oil, dimexide, ether, chloroform, benzyl benzoate, or another non-water medium, classify as non-aqueous solution.

### RULE_SOL_NONAQ_002 — Volatile solvent protection
If system contains volatile solvent, technology must avoid unnecessary heating and prolonged open exposure.

### RULE_SOL_NONAQ_003 — Filtration caution for volatile systems
Do not add filtration by default if filtration risks volatile losses or content change, unless required.

### RULE_SOL_NONAQ_004 — Solvent compatibility check
The engine must validate compatibility of mixed solvent phases and issue a warning if complete miscibility is doubtful.

### RULE_SOL_NONAQ_005 — Water branch isolation
KVO rules intended for aqueous solutions must not be auto-applied to non-aqueous systems.

---

## 7. Drops

### RULE_DROPS_001 — Drops subtype classification
Drops must be classified by route:
- oral drops
- nasal drops
- ear drops
- eye drops
- external drops

### RULE_DROPS_002 — Sterility sensitivity
Eye drops require stricter handling than routine oral drops. If sterility-related metadata is absent, engine must warn instead of inventing full sterile protocol.

### RULE_DROPS_003 — Dose parsing for oral drops
If signa specifies drops count per dose, the engine must preserve both drop count and volume estimate only when calibrated drop factor is available.

### RULE_DROPS_004 — No generic ml conversion for drops
Do not convert drops to ml using a universal constant unless explicit reference factor exists.

---

## 8. Powders

### RULE_POW_001 — Powder classification
Powders must be classified as:
- divided
- undivided
- simple
- compound
- with potent substances
- with poisonous substances
- with triturations

### RULE_POW_002 — Per-dose calculation
For divided powders, all active masses must be reduced to per-dose values before dose validation.

### RULE_POW_003 — Minimum technological mass control
If one divided powder dose is too small for accurate compounding, engine must trigger technological correction block.

### RULE_POW_004 — Triturations for microdoses
If active substance mass falls below accurate weighability threshold and a reference trituration exists, engine should prefer trituration pathway.

### RULE_POW_005 — Combined microdose protection
If several microdose ingredients occur in one divided powder, engine must prevent accumulated rounding error across doses and total batch.

### RULE_POW_006 — Homogenization order
Powders should be mixed in an order that improves homogeneity, usually from smaller mass to larger mass with geometric dilution when relevant.

---

## 9. Triturations

### RULE_TRIT_001 — Trituration definition
A trituration is a predefined diluted powder mixture used to safely and accurately introduce very small doses of potent substances.

### RULE_TRIT_002 — Trituration selection
If a substance requires trituration and a standard concentration exists, engine must calculate based on the selected trituration concentration, not on raw substance mass directly in the working mix.

### RULE_TRIT_003 — Reverse calculation
For trituration concentration `p`:
`m_trituration = m_active_required / p`

### RULE_TRIT_004 — Excipients from trituration are counted
The inert mass introduced with trituration must be counted in final powder mass and packaging logic.

### RULE_TRIT_005 — Trituration traceability
PPC must show both:
- active mass required
- trituration mass used

---

## 10. Poisonous and potent substances

### RULE_SAFE_001 — Poison / potent detection
Detection may rely on structured flags such as:
- `IsListA_Poison == true`
- `IsListB_Potent == true`
- curated reference columns

### RULE_SAFE_002 — Independent safety block
Poison / potent validation must run independently of dosage-form calculation blocks.

### RULE_SAFE_003 — Mandatory dose control
For poisonous and potent substances, dose control must run whenever route and signa enable per-dose or daily-dose interpretation.

### RULE_SAFE_004 — Missing signa warning
If dose-critical substance exists and signa is missing or not parseable, engine must raise `dose_control_unresolved`.

### RULE_SAFE_005 — Safety-first interpretation
If signa can be parsed in more than one way, choose the safer lower-confidence warning path and do not falsely claim validity.

---

## 11. Dose control and signa parsing

### RULE_DOSE_001 — Common parser
All dose-control blocks must use one common parser for signa / directions.
No duplicated parsing logic across solutions, drops, powders, poison, and potent blocks.

### RULE_DOSE_002 — Supported volume expressions
The parser must support at least:
- `по 1 чайной ложке`
- `по 1 ч. л.`
- `по 1 десертной ложке`
- `по 1 ст. ложке`
- `по 1 стол. л.`
- `по 10 мл`
- `по 15 ml`
- `1 teaspoon`
- `1 tablespoon`

### RULE_DOSE_003 — Standard spoon conversions
Unless local policy overrides, the engine may use configured reference conversions, e.g.:
- teaspoon = 5 ml
- dessert spoon = 10 ml
- tablespoon = 15 ml

These must be configurable, not hard-coded across modules.

### RULE_DOSE_004 — Frequency parsing
The parser must support at least:
- `3 раза в день`
- `3 р/д`
- `3 р. в день`
- `двічі на добу`
- `bid`, `tid`, `qid` if such notation is supported in the app policy

### RULE_DOSE_005 — Per-dose amount
If total amount of substance in the full volume is known and single dose volume is known:
`m_per_dose = m_total / number_of_doses`

where:
`number_of_doses = V_total / V_single_dose`

for homogeneous oral liquid systems.

### RULE_DOSE_006 — Daily amount
If intake frequency is known:
`m_per_day = m_per_dose × intake_frequency`

### RULE_DOSE_007 — Integer-dose caution
If total volume does not divide cleanly by dose volume, parser must show this as approximate and not silently round.

### RULE_DOSE_008 — Unparseable route warning
If signa does not clearly provide dose units or frequency, engine should provide the available calculation subset and a warning.

---

## 12. Ointments and semisolids

### RULE_OMG_001 — Ointment base classification
Ointment bases must be normalized by type:
- hydrocarbon
- absorption
- water-removable
- water-soluble
- combined

### RULE_OMG_002 — Active introduction path
Active substances in ointments must be introduced by one of:
- dissolution in suitable phase
- levigation
- trituration / micronized dispersion
- incorporation into melted base if allowed

### RULE_OMG_003 — Heating restriction
Heating must be controlled by base and volatile component stability. Do not generalize melting/heating to all ointments.

---

## 13. Packaging and labeling

### RULE_PACK_001 — Package from stability and route
Package selection must depend on:
- route
- phase
- volatility
- light sensitivity
- viscosity
- sterility sensitivity

### RULE_PACK_002 — True solution default label
For oral true solution, default label may include internal use label but must not include `shake` unless justified.

### RULE_PACK_003 — Light protection label
Protect-from-light labeling must appear only when ingredient or preparation stability indicates it.

### RULE_PACK_004 — Cool storage label
Cool storage must not be assigned universally. It must follow stability rule or explicit source data.

### RULE_PACK_005 — Missing mandatory metadata
If patient name, prescription number, batch data, or signatures are required by the selected PPC format and absent, emit warnings instead of inventing values.

---

## 14. Quality control

### RULE_QC_001 — Final preparation vs stock concentrate
Quality-control text must correspond to what is actually being prepared:
- final dosage form
- not the stock concentrate unless stock concentrate is the prepared object

### RULE_QC_002 — True solution physical control
For a true oral solution, typical final control includes:
- appearance / clarity
- absence of mechanical particles
- conformity of final volume
- labeling and packaging check

### RULE_QC_003 — No stock-method QC leakage
Methods such as titration / refractometry for concentrate standardization must not be automatically copied into final PPC for a mixture prepared from ready concentrates.

### RULE_QC_004 — Route-specific additions
Additional QC rules may be added by route and dosage form, but only when source-backed.

---

## 15. PPC generation

### RULE_PPC_001 — Structured PPC sections
PPC must be generated from structured sections, not one continuous improvised paragraph.

Recommended sections:
- Input data
- Normalization
- Mathematical justification
- Auxiliary safety calculations
- Technological justification
- Technology order
- Final control
- Packaging and storage
- Warnings

### RULE_PPC_002 — No duplicated sections
The renderer must not duplicate identical technology blocks in the same PPC unless explicitly requested.

### RULE_PPC_003 — Terminology consistency
One preparation should be referred to consistently. If the final object is a mixture/solution, do not accidentally call it a stock concentrate in QC text.

### RULE_PPC_004 — Explain assumptions in PPC
If any inferred step was used, PPC must include a concise note or warning.

### RULE_PPC_005 — Technology order consistency
If the calculated technology path is burette concentrate path, operation order should reflect that path and not contradict ad logic.

### RULE_PPC_006 — Machine-readable outputs
The engine must be able to return PPC both as human-readable text and as structured JSON sections.

---

## 16. Validation and conflicts

### RULE_VAL_001 — Conflict registry
Validation engine must detect at minimum:
- ingredient form conflict
- multiple ad conflict
- fixed water vs ad conflict
- target volume missing
- solution treated as solid
- KVO applied to ready solution
- stock QC text inserted into final preparation QC
- unsupported signa
- incompatible solvent phases

### RULE_VAL_002 — Warning severity
Warnings must be classified:
- info
- caution
- critical

### RULE_VAL_003 — Critical calculation stop
Stop full deterministic calculation only when the missing/conflicting data blocks safe calculation.
Otherwise calculate safe subset and warn.

---

## 17. Minimal implementation order

### RULE_IMPL_001 — Phase order
Recommended implementation order:
1. Solutions
2. ad logic
3. dose parser
4. PPC renderer
5. Powders
6. Triturations
7. Poison / potent blocks
8. Drops
9. Ointments
10. advanced compatibility and validation

---

## 18. Required outputs per calculation

### RULE_OUT_001 — Calculation output contract
Every solved formulation should produce structured output with at least:
- `classification`
- `ingredient_roles`
- `normalized_values`
- `calculation_steps`
- `technology_steps`
- `quality_control`
- `packaging`
- `labels`
- `warnings`
- `ppc_sections`

### RULE_OUT_002 — Solution output minimum
For solutions, output must include at least:
- target final volume
- required masses
- selected concentrate strengths
- individual concentrate volumes
- total counted liquid volumes
- solvent to add / ad result
- KVO applied or not applied with reason
- technology order
2) ENGINE_ARCHITECTURE.md
# ENGINE_ARCHITECTURE.md

Version: 1.0
Goal: architecture for a deterministic pharmaceutical compounding engine for URAN Pharma.

---

## 1. Architectural goals

The engine must be:
- deterministic
- explainable
- modular
- testable
- source-traceable
- conservative in unsafe ambiguity
- suitable for Swift / SwiftUI app integration

It is not a chatbot engine.
It is a rule-based pharmaceutical calculation and validation engine.

---

## 2. High-level pipeline

```text
Raw Recipe Input
    ↓
Parser Layer
    ↓
Normalization Layer
    ↓
Classification Layer
    ↓
Rule Engine
    ↓
Calculation Engine
    ↓
Validation Engine
    ↓
PPC Renderer / Structured Output

3. Core modules
3.1 Parser Layer
Purpose:
	•	parse free-text prescription
	•	parse structured recipe cards
	•	extract ingredients, amounts, units, concentration, ad markers, signa, dosage form, route
Responsibilities:
	•	tokenize medical / pharmaceutical notation
	•	normalize Latin/RU/UA forms
	•	detect concentration syntax %, 1:n, ad, aa/ana, drops, spoon directions
	•	preserve unresolved raw fragments
Suggested components:
	•	RecipeTextParser
	•	IngredientParser
	•	ConcentrationParser
	•	SignaParserInputExtractor
	•	LatinAbbreviationResolver
Outputs:
	•	ParsedPrescription
	•	parser warnings
3.2 Normalization Layer
Purpose: convert parsed fragments into canonical machine objects.
Responsibilities:
	•	normalize units to canonical forms
	•	convert synonyms of dosage forms
	•	classify route
	•	normalize ingredient names to registry IDs where possible
	•	assign ingredient roles and phases
	•	identify ad, q.s., aa
Suggested components:
	•	IngredientNormalizer
	•	UnitNormalizer
	•	DosageFormNormalizer
	•	IngredientRoleResolver
	•	PhaseResolver
Outputs:
	•	NormalizedPrescription
3.3 Classification Layer
Purpose: determine which pharmaceutical processing path should be used.
Responsibilities:
	•	detect formulation class: solution, powder, drops, ointment, etc.
	•	detect subtype: aqueous / non-aqueous / standard solution / burette path
	•	detect safety blocks: poison, potent, trituration requirement
	•	detect target volume logic and ad path
Suggested components:
	•	FormulationClassifier
	•	SolutionClassifier
	•	SafetyClassifier
	•	DoseControlClassifier
Outputs:
	•	FormulationContext
	•	subtype flags
3.4 Rule Engine
Purpose: apply deterministic pharmaceutical rules from PHARM_RULES.md and curated tables.
Responsibilities:
	•	choose applicable rule sets
	•	preserve priority order
	•	record rule trace
	•	resolve conflicts conservatively
	•	expose which rule caused which step
Suggested components:
	•	RuleRegistry
	•	RuleSelector
	•	RuleExecutor
	•	RuleTraceCollector
Possible rule namespaces:
	•	CoreRules
	•	SolutionRules
	•	AdRules
	•	PowderRules
	•	TriturateRules
	•	SafetyRules
	•	DoseRules
	•	PackagingRules
	•	PpcRules
Outputs:
	•	AppliedRuleSet
	•	rule trace
3.5 Calculation Engine
Purpose: perform mathematics only after classification and rule selection.
Responsibilities:
	•	calculate required masses
	•	calculate concentrate volumes
	•	calculate solvent by ad
	•	calculate KVO displacement if applicable
	•	calculate per-dose / daily-dose values
	•	compute final batch quantities
Suggested components:
	•	SolutionCalculator
	•	AdCalculator
	•	KvoCalculator
	•	DoseCalculator
	•	PowderCalculator
	•	TriturateCalculator
Outputs:
	•	CalculationResult
	•	CalculationStep[]
3.6 Validation Engine
Purpose: check pharmaceutical consistency and safety after or alongside calculations.
Responsibilities:
	•	detect conflicts
	•	detect unresolved cases
	•	detect impossible / contradictory states
	•	classify warning severity
	•	block invalid final assertions
Suggested components:
	•	ConflictValidator
	•	SafetyValidator
	•	SignaValidator
	•	PhaseCompatibilityValidator
	•	PpcConsistencyValidator
Outputs:
	•	ValidationReport
	•	Warning[]
	•	CriticalIssue[]
3.7 PPC Renderer
Purpose: render both human-readable and structured pharmaceutical preparation cards.
Responsibilities:
	•	render standard section order
	•	avoid duplicated sections
	•	reflect actual preparation object
	•	generate front/back formats
	•	preserve trace and warnings
Suggested components:
	•	PpcSectionBuilder
	•	BackSideRenderer
	•	FrontSideRenderer
	•	StructuredJsonRenderer
Outputs:
	•	PPCDocument
	•	PPCJson

4. Data model design
ParsedPrescription
Fields:
	•	rawText
	•	dosageFormRaw
	•	ingredientsRaw[]
	•	signaRaw
	•	patientData
	•	meta
NormalizedPrescription
Fields:
	•	dosageForm
	•	route
	•	ingredients[]
	•	target
	•	signa
	•	sourceLanguage
	•	warnings[]
NormalizedIngredient
Fields:
	•	id
	•	displayName
	•	normalizedName
	•	role
	•	presentationKind
	•	phase
	•	amountValue
	•	amountUnit
	•	concentration
	•	ratio
	•	isAd
	•	isAna
	•	referenceMetadata
	•	safetyFlags
FormulationContext
Fields:
	•	formulationType
	•	solutionSubtype
	•	hasAd
	•	targetVolume
	•	countedLiquids[]
	•	solidIngredients[]
	•	safetyProfile
	•	requiresDoseControl
	•	confidence
CalculationStep
Fields:
	•	stepId
	•	formula
	•	substitution
	•	result
	•	unit
	•	ruleId
	•	confidence
Warning
Fields:
	•	code
	•	severity
	•	message
	•	relatedIngredientId
	•	ruleId
CalculationResult
Fields:
	•	classification
	•	normalizedValues
	•	individualResults
	•	derivedResults
	•	technologyPlan
	•	packagingPlan
	•	qcPlan
	•	warnings
	•	trace

5. Solution-specific architecture
5.1 Why separate solution module
Solutions are the most calculation-heavy and ambiguity-prone class. They need dedicated context and dedicated validators.
5.2 SolutionContext
Recommended dedicated object:
	•	solutionSubtype
	•	targetVolume
	•	finalAdjustmentMode
	•	aqueousLiquids[]
	•	nonAqueousLiquids[]
	•	concentrates[]
	•	finishedSolutions[]
	•	drySolids[]
	•	otherLiquids[]
	•	kvoApplicable
	•	kvoContribution
	•	requiresFiltration
	•	requiresDarkGlass
	•	requiresShakeLabel
	•	safetyWarnings[]
5.3 SolutionContextBuilder
Purpose:
	•	build a fully classified context before calculation
Responsibilities:
	•	exclude presentationKind == .solution from solids
	•	identify concentrate path
	•	identify standard solution path
	•	resolve ad target
	•	separate counted liquids from final-adjustment solvent
5.4 SolutionCalculator
Responsibilities:
	•	target concentration -> required mass
	•	required mass -> concentrate volume
	•	sum concentrate volumes
	•	compute solvent/ad
	•	compute solid percentage for dry path
	•	compute KVO branch only when valid
5.5 SolutionTechnologyPlanner
Responsibilities:
	•	generate ordered operations
	•	distinguish:
	◦	dry dissolution path
	◦	burette concentrate path
	◦	standard-solution path
	◦	non-aqueous path
5.6 SolutionValidation
Checks at minimum:
	•	ready solution included in solids
	•	KVO applied to concentrate path
	•	ad conflict
	•	wrong target inference
	•	unjustified filtration
	•	unjustified shake label
	•	stock QC text leaked into final PPC

6. Safety subsystem
Safety must be independent from formulation subtype.
SafetyProfile
Contains:
	•	isListA
	•	isListB
	•	isPotent
	•	requiresDoseControl
	•	requiresSpecialPackaging
	•	specialWarnings[]
SafetyEngine
Responsibilities:
	•	detect poison/potent rules
	•	require signa parser when needed
	•	compare calculated per-dose/daily-dose values against reference limits if available

7. Signa and dose parser subsystem
This must be one shared subsystem.
SignaDoseParser
Responsibilities:
	•	parse spoon expressions
	•	parse ml expressions
	•	parse frequency
	•	parse route hints
	•	parse drops if applicable
DoseInterpretation
Fields:
	•	singleDoseValue
	•	singleDoseUnit
	•	singleDoseMl
	•	frequencyPerDay
	•	confidence
	•	rawMatches[]
This parser should never be duplicated inside separate blocks.

8. Rendering subsystem
Recommended section builders:
	•	InputSectionBuilder
	•	NormalizationSectionBuilder
	•	MathSectionBuilder
	•	SafetySectionBuilder
	•	TechnologySectionBuilder
	•	ControlSectionBuilder
	•	PackagingSectionBuilder
	•	WarningsSectionBuilder
Rule: renderers must not recalculate. They only format already-decided structured results.

9. Test strategy
Three layers of testing are required.
9.1 Unit tests
For isolated formula and rule behavior.
Examples:
	•	percent to mass
	•	concentrate volume
	•	ad calculation
	•	spoon parsing
	•	trituration reverse calculation
9.2 Scenario tests
For complete formulations.
Examples:
	•	burette solution with multiple concentrates
	•	dry aqueous solution with KVO
	•	multiple liquids + ad
	•	poisonous powder with trituration
9.3 Golden PPC tests
For final rendered text / section structure.
Examples:
	•	no duplicated technology block
	•	no stock QC text in final mixture PPC
	•	no unjustified shake label

10. Recommended project structure
PharmaEngine/
  Core/
    RuleRegistry.swift
    RuleTrace.swift
    Warning.swift
    Units.swift

  Parser/
    RecipeTextParser.swift
    IngredientParser.swift
    ConcentrationParser.swift
    SignaInputExtractor.swift

  Normalization/
    IngredientNormalizer.swift
    UnitNormalizer.swift
    RoleResolver.swift
    PhaseResolver.swift

  Classification/
    FormulationClassifier.swift
    SolutionClassifier.swift
    SafetyClassifier.swift

  Context/
    FormulationContext.swift
    SolutionContext.swift
    SafetyProfile.swift

  Calculators/
    SolutionCalculator.swift
    AdCalculator.swift
    KvoCalculator.swift
    DoseCalculator.swift
    PowderCalculator.swift
    TriturateCalculator.swift

  Validators/
    ConflictValidator.swift
    SolutionValidator.swift
    DoseValidator.swift
    PpcConsistencyValidator.swift

  Technology/
    SolutionTechnologyPlanner.swift
    PowderTechnologyPlanner.swift

  Rendering/
    PpcSectionBuilder.swift
    BackSideRenderer.swift
    FrontSideRenderer.swift
    JsonRenderer.swift

  Reference/
    ExtempReferenceRepository.swift
    SafetyReferenceRepository.swift
    PackagingReferenceRepository.swift

  Tests/
    Unit/
    Scenarios/
    Golden/

11. Implementation roadmap
Phase 1 — Solutions core
Implement first:
	•	parser normalization for solution ingredients
	•	role resolution
	•	ad logic
	•	concentrate volume formulas
	•	solution validator
	•	solution PPC sections
	•	scenario tests for solutions
Phase 2 — Dose parser
Implement:
	•	shared signa parser
	•	oral liquid dose control
	•	poison/potent integration
Phase 3 — Powders and triturations
Implement:
	•	minimum technological mass
	•	trituration engine
	•	combined microdose protection
Phase 4 — Drops, ointments, advanced validation
Implement:
	•	drop route variants
	•	ointment phase logic
	•	solvent compatibility
	•	advanced packaging/stability

12. Non-negotiable design rules
	1	Do not mix parsing with calculations.
	2	Do not mix rendering with calculations.
	3	Do not hard-code unsafe heuristics inside UI layer.
	4	All warnings must be structured.
	5	All explainable calculations must have formula trace.
	6	Every module must be testable without UI.
	7	presentationKind == solution must never silently behave like a dry substance.
	8	ad logic must be handled centrally, not in many scattered places.
	9	Shared signa parsing must be reused everywhere.
	10	Rendered PPC must match actual calculated object.

13. Desired final contract for app integration
The UI should receive one structured object, e.g. EngineResponse:
{
  "status": "ok",
  "classification": "aqueous_burette_solution",
  "confidence": "exact",
  "result": {
    "targetVolumeMl": 150,
    "concentrates": [
      {"name": "Sol. Glucosi 50%", "volumeMl": 12},
      {"name": "Sol. Coffeini-natrii benzoatis 10%", "volumeMl": 10},
      {"name": "Sol. Natrii bromidi 20%", "volumeMl": 15}
    ],
    "waterToAddMl": 113
  },
  "technology": [...],
  "qc": [...],
  "packaging": [...],
  "warnings": [...],
  "ppc": {...},
  "trace": [...]
}
This allows the app to:
	•	show concise result
	•	show full PPC
	•	show warnings
	•	show math explanation
	•	remain stable across UI redesigns
## 3) 
}
4) EDGE_CASES.md
# EDGE_CASES.md

Version: 1.0
Purpose: critical edge cases that commonly break pharmaceutical logic engines and must be explicitly handled.

---

## 1. Solutions — core ambiguity cases

### EDGE_SOL_001 — Ready solution accidentally treated as dry substance
Example:
- `Sol. Furacilini 1:5000 50 ml`
- `Aqua purificata ad 100 ml`

Risk:
- ready solution enters `Σ solids`
- KVO wrongly applied
- solvent amount becomes wrong

Expected behavior:
- classify ready solution as liquid
- exclude from solid mass branch
- compute water = 50 ml

---

### EDGE_SOL_002 — Target solution concentration + reference stock concentration
Example:
- `Sol. Natrii bromidi 2% 150 ml`
with reference stock `20%`

Risk:
- engine confuses final target concentration with actual ingredient volume
- computes 150 ml of 20% instead of 15 ml

Expected behavior:
- compute required mass 3 g
- compute stock volume 15 ml
- then use ad logic

---

### EDGE_SOL_003 — Several liquid ingredients + ad
Example:
- tincture 3 ml
- syrup 20 ml
- concentrate 5 ml
- water ad 200 ml

Risk:
- subtracting only one liquid
- target chosen by largest-liquid fallback
- over/underfilling

Expected behavior:
- sum all counted liquids
- water = target - all counted liquids
- warning only if target source is unclear

---

### EDGE_SOL_004 — Explicit water volume plus ad water
Example:
- `Aq. purif. 100 ml`
- `Aq. purif. ad 200 ml`

Risk:
- double counting or silent acceptance of contradiction

Expected behavior:
- raise conflict warning
- avoid fake deterministic final statement without resolution

---

### EDGE_SOL_005 — KVO applied to ready concentrates
Example:
all substances introduced through stock solutions.

Risk:
- engine subtracts concentrate volumes and also applies dry-substance displacement

Expected behavior:
- KVO disabled
- reason shown explicitly

---

### EDGE_SOL_006 — Largest-liquid wrong target inference
Example:
- solution contains 100 ml aromatic water + 5 ml tincture + `ad 120 ml`

Risk:
- engine assumes 100 ml aromatic water is target liquid and ignores actual ad marker

Expected behavior:
- explicit ad target has priority over size-based fallback

---

### EDGE_SOL_007 — Standard solution special-case false activation
Example:
text contains `Demyanovich` in note or comment.

Risk:
- engine switches to method No.2 logic without explicit indication

Expected behavior:
- do not activate special case by name mention alone

---

### EDGE_SOL_008 — True solution given shake label by default
Example:
clear oral solution from concentrates.

Risk:
- methodologically wrong labeling

Expected behavior:
- no shake label unless justified by heterogeneity/instability rule

---

### EDGE_SOL_009 — QC text of stock concentrate leaks into final mixture PPC
Example:
mixture prepared from ready concentrates.

Risk:
- PPC says `after preparation the concentrate is subject to chemical control`

Expected behavior:
- QC must describe final mixture, not stock solution standardization

---

### EDGE_SOL_010 — Filtration added automatically to all solutions
Risk:
- false technology instruction
- may be harmful for volatile systems

Expected behavior:
- filtration only when actually indicated

---

## 2. Signa and dose control cases

### EDGE_DOSE_001 — Spoon expression variants
Forms to support:
- `по 1 ст. ложке`
- `по 1 стол. л.`
- `по 1 tbsp`
- `1 tablespoon`

Risk:
- parser supports one spelling and misses others

Expected behavior:
- normalize all to configured spoon volume

---

### EDGE_DOSE_002 — Frequency variants
Forms:
- `3 раза в день`
- `3 р/д`
- `3 р. в день`
- `тричі на добу`
- `tid`

Risk:
- partial frequency parsing

Expected behavior:
- parse frequency consistently in one shared parser

---

### EDGE_DOSE_003 — Non-divisible volume by dose volume
Example:
100 ml total, 15 ml per dose.

Risk:
- engine silently rounds dose count to 6 or 7

Expected behavior:
- show approximate dose count and confidence downgrade

---

### EDGE_DOSE_004 — Potent substance with vague signa
Example:
`take as directed`

Risk:
- no dose check despite safety risk

Expected behavior:
- `dose_control_unresolved` warning

---

## 3. Powders and triturations

### EDGE_POW_001 — Several microdose actives in one divided powder
Risk:
- separate rounding of each active introduces large batch error

Expected behavior:
- combined rounding protection
- total-batch reconciliation

---

### EDGE_POW_002 — Microdose below weighability without trituration
Risk:
- impossible accurate weighing

Expected behavior:
- require trituration or issue critical warning

---

### EDGE_POW_003 — Trituration inert mass ignored
Risk:
- wrong final dose mass and packaging mass

Expected behavior:
- include inert trituration mass in totals

---

### EDGE_POW_004 — Per-dose vs total-batch confusion
Risk:
- reference limit checked against batch total instead of one dose

Expected behavior:
- divided powders must validate per-dose first

---

## 4. Drops

### EDGE_DROP_001 — Universal drop-to-ml conversion
Risk:
- wrong dose due to different viscosities/drop factors

Expected behavior:
- no universal conversion unless explicit calibrated factor exists

---

### EDGE_DROP_002 — Eye drops treated like oral drops
Risk:
- missing sterility-related warning

Expected behavior:
- route-sensitive logic

---

## 5. Non-aqueous systems

### EDGE_NONAQ_001 — Alcohol-containing solution gets heating instruction
Risk:
- evaporation and concentration change

Expected behavior:
- avoid unnecessary heating by default

---

### EDGE_NONAQ_002 — Immiscible or poorly miscible phases treated as true solution
Example:
water + oil without emulsifier

Risk:
- wrong dosage-form classification

Expected behavior:
- warn about compatibility / possible emulsion or phase separation

---

## 6. Rendering and UX consistency

### EDGE_PPC_001 — Duplicate technology section
Risk:
- PPC repeats full technology twice

Expected behavior:
- renderer deduplicates sections or blocks repeated content

---

### EDGE_PPC_002 — Inconsistent terminology
Example:
same object called `mixture`, `solution`, then `concentrate`

Risk:
- user distrust and methodological confusion

Expected behavior:
- consistent terminology based on final object class

---

### EDGE_PPC_003 — Warnings silently disappear from concise view
Risk:
- user sees nice result and misses conflict

Expected behavior:
- critical warnings must survive both full and compact render modes

---

## 7. Data and reference integrity

### EDGE_DATA_001 — Ingredient has conflicting metadata
Example:
CSV says `solution`, JSON says `solid`.

Risk:
- unstable behavior between builds

Expected behavior:
- conflict warning with source trace

---

### EDGE_DATA_002 — Missing concentrate reference
Example:
recipe requires burette path but no stock concentration is available.

Risk:
- engine invents a stock strength

Expected behavior:
- do not invent; mark unresolved and suggest direct-dissolution path only if source-backed

---

### EDGE_DATA_003 — Missing KVO reference for a dry substance
Risk:
- engine guesses displacement coefficient

Expected behavior:
- do not guess; either skip KVO with warning or block branch depending on policy

---

## 8. Priority cases the engine must always pass before release

1. Ready solution never becomes a solid.
2. `ad` beats largest-liquid fallback.
3. KVO is never applied to ready concentrates.
4. Shared signa parser is reused everywhere.
5. Final PPC never contains stock-concentrate QC text unless stock concentrate itself is being prepared.
6. True clear solution does not get `shake before use` by default.
7. Special named methods do not activate from weak text hints alone.
8. Potent / poisonous substances cannot bypass dose-control warnings. сначала закинь в проект только PHARM_RULES.md и TEST_RECIPES.json, и заставь Codex пройти все solution-кейсы без регрессий.
