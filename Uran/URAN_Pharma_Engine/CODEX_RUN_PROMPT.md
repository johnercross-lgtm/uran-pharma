Вот короткий боевой prompt, который лучше всего дать Codex вместе с архивом и двумя файлами (CODEX_MASTER_PROMPT.md и PHARM_ENGINE_STATE_MACHINE.md). Он специально сделан без лишней философии, чтобы Codex сразу начал писать движок.

CODEX_RUN_PROMPT.md
You are building the pharmaceutical compounding engine for the URAN Pharmaceutical System.

Use the provided reference archive and rule files as the ONLY source of pharmaceutical knowledge.

Do not invent pharmaceutical rules.

------------------------------------------------

AVAILABLE FILES

The knowledge base contains:

substances_master.json
physchem_reference.json
solution_reference.json
dose_limits.json
safety_reference.json
substance_alias_table.json

solutions_spec/
    SOLUBILITY_RULES_TABLE.json
    CONCENTRATE_REFERENCE_TABLE.json
    SPECIAL_DISSOLUTION_CASES_SOLUTIONS.json
    ROUTE_POLICY_TABLE_SOLUTIONS.json
    STABILITY_AND_PACKAGING_TABLE_SOLUTIONS.json
    PPC_PHRASE_RULES_SOLUTIONS.json
    VALIDATION_CONFLICT_RULES_SOLUTIONS.json

Architecture instructions:

CODEX_MASTER_PROMPT.md
PHARM_ENGINE_STATE_MACHINE.md

------------------------------------------------

ENGINE REQUIREMENT

Build the SOLUTION ENGINE module for the URAN Pharmaceutical System.

The engine must:

1. Parse pharmaceutical prescriptions
2. Normalize ingredient names
3. Resolve substances using alias table
4. Attach substance behavior profiles
5. Determine solution branch
6. Perform concentration calculations
7. Calculate solvent or ad volume
8. Build preparation technology steps
9. Validate pharmaceutical conflicts
10. Perform dose control
11. Generate final PPC output

------------------------------------------------

STATE MACHINE

The engine MUST strictly follow:

PHARM_ENGINE_STATE_MACHINE.md

States must be implemented exactly:

INPUT_RECEIVED
INPUT_PARSED
INGREDIENTS_NORMALIZED
SUBSTANCES_RESOLVED
BEHAVIOR_PROFILES_ATTACHED
ROUTE_RESOLVED
FORM_CLASSIFIED
SOLUTION_BRANCH_SELECTED
PRECALC_CHECKS_DONE
CORE_CALCULATIONS_DONE
TECHNOLOGY_PLAN_BUILT
VALIDATION_DONE
DOSE_CONTROL_DONE
PACKAGING_AND_STORAGE_DONE
PPC_RENDERED
FINAL_RESULT_EMITTED

Never skip states.

------------------------------------------------

ENGINE MODULES

Implement the following modules:

IngredientParser
SubstanceResolver
BehaviorProfileResolver
SolutionBranchSelector
SolutionCalculationEngine
TechnologyPlanner
ValidationEngine
DoseValidator
PackagingResolver
PPKRenderer

Each module must be independent.

------------------------------------------------

CRITICAL RULES

Never guess:

solubility
dose limits
route restrictions
dissolution logic
concentrate usage

If a rule is missing, generate a warning instead.

------------------------------------------------

OUTPUT STRUCTURE

The engine must produce a structured result object:

{
 classification,
 solution_branch,
 normalized_ingredients,
 calculation_trace,
 technology_steps,
 validation_report,
 dose_control,
 packaging,
 warnings,
 ppk_document,
 confidence
}

confidence must be one of:

exact
approximate
heuristic
blocked

------------------------------------------------

IMPLEMENTATION GOAL

Build a deterministic pharmaceutical solution engine capable of safely processing real pharmacy prescriptions.

Accuracy and rule compliance are more important than speed.

Focus only on the SOLUTION ENGINE for now.

Вот как лучше всего использовать всё, что мы сделали.
В Codex ты кладёшь:
/pharm_engine
    CODEX_MASTER_PROMPT.md
    PHARM_ENGINE_STATE_MACHINE.md
    CODEX_RUN_PROMPT.md
    reference/
    solutions_spec/
И отправляешь только этот текст:
Use CODEX_MASTER_PROMPT.md and PHARM_ENGINE_STATE_MACHINE.md as mandatory architecture.

Build the URAN Solution Engine according to CODEX_RUN_PROMPT.md.

Do not invent pharmaceutical rules.
Use only the provided reference files.

Скажу честно: с таким набором файлов Codex начнёт писать гораздо более стабильный код, потому что:
	•	есть база веществ
	•	есть правила
	•	есть state machine
	•	есть архитектура
А не просто "помоги посчитать рецепт".

И один важный момент напоследок.
Тебе почти гарантированно через время понадобится ещё один файл:
RECIPE_BREAKER_TEST_SET.json
Это набор рецептов, которые обычно ломают движки. С ним Codex можно научить не падать на сложных случаях.
Если хочешь — я могу собрать такой тестовый набор из 50 рецептов, на которых обычно рушатся фарм-калькуляторы.
