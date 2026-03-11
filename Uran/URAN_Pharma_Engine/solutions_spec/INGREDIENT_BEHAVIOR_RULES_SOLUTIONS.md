{\rtf1\ansi\ansicpg1251\cocoartf2868
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 # INGREDIENT_BEHAVIOR_RULES_SOLUTIONS.md\
\
Version: 1.0\
Purpose: behavior-level rules for ingredients used in the pharmaceutical solutions engine.\
Goal: describe not only what an ingredient is, but how it behaves technologically inside a solution.\
\
---\
\
## 0. Core principle\
\
Every ingredient used in a solution must receive a behavior profile before calculation.\
\
The engine must determine not only:\
- name\
- amount\
- unit\
- concentration\
\
but also:\
- how the ingredient is introduced\
- whether it counts as liquid or solid\
- whether it affects ad\
- whether it affects KVO\
- whether it requires separate dissolution\
- whether it must be added at the end\
- whether heating is allowed\
- whether filtration is allowed\
- whether route/stability restrictions apply\
\
If behavior profile is incomplete:\
- engine must not invent unsafe technology\
- engine may calculate only safe deterministic subset\
- warning must be attached\
\
---\
\
## 1. Required behavior profile fields\
\
Each ingredient in SolutionsEngine should have:\
\
- `behaviorType`\
- `introductionMode`\
- `countsAsLiquid`\
- `countsAsSolid`\
- `affectsAd`\
- `affectsKvo`\
- `solubilityClass`\
- `phaseType`\
- `requiresSeparateDissolution`\
- `requiredPreDissolutionSolvent`\
- `addAtEnd`\
- `orderPriority`\
- `heatPolicy`\
- `volatilityPolicy`\
- `filtrationPolicy`\
- `lightSensitive`\
- `sterilitySensitive`\
- `routeRestrictions`\
- `compatibilityHints`\
\
---\
\
## 2. Canonical enums\
\
### 2.1 behaviorType\
Possible values:\
- purifiedWater\
- aqueousSolvent\
- drySubstance\
- readySolution\
- standardSolution\
- concentrate\
- tincture\
- liquidExtract\
- dryExtract\
- syrup\
- aromaticWater\
- alcohol\
- glycerin\
- oil\
- volatileSolvent\
- mixedLiquid\
- undefined\
\
### 2.2 introductionMode\
Possible values:\
- direct_dissolve\
- as_ready_solution\
- as_standard_solution\
- as_concentrate\
- as_tincture\
- as_liquid_extract\
- as_aromatic_water\
- as_syrup\
- as_non_aqueous_solvent\
- requires_separate_dissolution\
- requires_pre_mixing\
- add_last\
- add_after_cooling\
- unresolved\
\
### 2.3 solubilityClass\
Possible values:\
- freely_soluble\
- soluble\
- sparingly_soluble\
- poorly_soluble\
- practically_insoluble\
- requires_co_solvent\
- unknown\
\
### 2.4 phaseType\
Possible values:\
- aqueous\
- hydroalcoholic\
- alcoholic\
- glycerinic\
- oily\
- volatileOrganic\
- mixed\
- unknown\
\
### 2.5 heatPolicy\
Possible values:\
- allow_heating\
- mild_heating_only\
- no_heating\
- add_after_cooling\
- unknown\
\
### 2.6 volatilityPolicy\
Possible values:\
- none\
- minimize_open_exposure\
- no_heating\
- add_last\
- avoid_filtration_if_possible\
- unknown\
\
### 2.7 filtrationPolicy\
Possible values:\
- normal_if_needed\
- avoid_if_possible\
- required_if_particles\
- no_default_filtration\
- unknown\
\
---\
\
## 3. Universal behavior rules\
\
### RULE_BEHAVIOR_001 \'97 Behavior profile required\
Every ingredient in solution calculations must receive a behavior profile before final classification.\
\
### RULE_BEHAVIOR_002 \'97 Missing profile warning\
If behavior profile is missing or partial:\
- raise `missing_behavior_profile`\
- do not invent technology-specific steps\
- allow only safe subset calculations\
\
### RULE_BEHAVIOR_003 \'97 CountsAs logic\
An ingredient must never have both:\
- `countsAsLiquid = true`\
- `countsAsSolid = true`\
unless it is explicitly modeled as a two-stage technological case.\
\
### RULE_BEHAVIOR_004 \'97 AffectsAd logic\
An ingredient affects `ad` if it contributes measurable liquid volume to the final preparation and is not itself the ad solvent marker.\
\
### RULE_BEHAVIOR_005 \'97 AffectsKvo logic\
An ingredient affects KVO only if:\
- it is introduced as a dry solid\
- it belongs to a branch where KVO is applicable\
- KVO reference exists or policy allows the branch\
\
### RULE_BEHAVIOR_006 \'97 Order-sensitive rule\
If ingredient has:\
- `addAtEnd = true`\
or\
- `orderPriority` indicating late addition\
\
then technology block must reflect this order.\
\
### RULE_BEHAVIOR_007 \'97 Route-sensitive rule\
If route requires special handling and profile does not include route support, engine must warn.\
\
---\
\
## 4. Purified water behavior\
\
### TYPE: purifiedWater\
\
#### Default profile\
- `behaviorType = purifiedWater`\
- `introductionMode = unresolved` unless explicitly fixed or ad\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = false` if it is the ad solvent marker itself\
- `affectsAd = true` if fixed water volume is specified\
- `affectsKvo = false`\
- `phaseType = aqueous`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = false`\
- `heatPolicy = allow_heating`\
- `volatilityPolicy = none`\
- `filtrationPolicy = normal_if_needed`\
\
### RULE_WATER_001 \'97 Water as ad solvent\
If water is marked `ad`, it defines final adjustment and is not summed as ordinary pre-counted liquid.\
\
### RULE_WATER_002 \'97 Fixed water\
If water has explicit volume and is not marked `ad`, it is a fixed counted liquid.\
\
### RULE_WATER_003 \'97 Water conflict\
If the same preparation contains fixed water and water `ad` without clear staged meaning, raise conflict.\
\
---\
\
## 5. Dry substance behavior\
\
### TYPE: drySubstance\
\
#### Default profile\
- `behaviorType = drySubstance`\
- `introductionMode = direct_dissolve` unless overridden\
- `countsAsLiquid = false`\
- `countsAsSolid = true`\
- `affectsAd = false`\
- `affectsKvo = true` only when KVO branch is valid\
- `requiresSeparateDissolution = false` unless flagged\
- `addAtEnd = false`\
- `heatPolicy = unknown`\
- `phaseType = unknown`\
\
### RULE_DRY_001 \'97 Dry substance enters solids\
Dry substances enter `\uc0\u931 solids`.\
\
### RULE_DRY_002 \'97 Dry substance may require separate dissolution\
If a substance has poor solubility or specific technology metadata, set:\
- `requiresSeparateDissolution = true`\
\
### RULE_DRY_003 \'97 Dry substance may be excluded from true solution path\
If `solubilityClass = practically_insoluble` or incompatible with selected solvent, do not keep it in true solution path without warning.\
\
---\
\
## 6. Ready solution behavior\
\
### TYPE: readySolution\
\
#### Default profile\
- `behaviorType = readySolution`\
- `introductionMode = as_ready_solution`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = depends on metadata`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = false`\
- `filtrationPolicy = no_default_filtration`\
\
### RULE_READY_SOL_001 \'97 Ready solution is never a solid\
A ready solution must never enter `\uc0\u931 solids`.\
\
### RULE_READY_SOL_002 \'97 Ready solution reduces ad solvent\
Ready solution volume is counted in `\uc0\u931 V_other_liquids` and reduces the volume of final ad solvent.\
\
### RULE_READY_SOL_003 \'97 No KVO for ready solution\
Ready solutions do not participate in KVO calculations.\
\
---\
\
## 7. Standard solution behavior\
\
### TYPE: standardSolution\
\
#### Default profile\
- `behaviorType = standardSolution`\
- `introductionMode = as_standard_solution`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = depends on reference`\
- `requiresSeparateDissolution = false`\
\
### RULE_STD_SOL_001 \'97 Standard solution is treated as liquid object\
It must be counted as liquid unless recipe explicitly demands preparation from raw components.\
\
### RULE_STD_SOL_002 \'97 No duplicate dry recalculation\
Do not convert standard solution into dry mass branch unless explicit formulation path says so.\
\
### RULE_STD_SOL_003 \'97 Special-case activation must be explicit\
Special method activation requires explicit strong marker, not weak textual mention.\
\
---\
\
## 8. Concentrate behavior\
\
### TYPE: concentrate\
\
#### Default profile\
- `behaviorType = concentrate`\
- `introductionMode = as_concentrate`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = usually aqueous unless specified`\
- `requiresSeparateDissolution = false`\
\
### RULE_CONCENTRATE_001 \'97 Concentrate counts only as liquid\
Concentrate contributes only volume in the final preparation branch.\
\
### RULE_CONCENTRATE_002 \'97 No KVO on concentrate path\
Concentrate must not trigger dry-substance KVO behavior for the same introduced amount.\
\
### RULE_CONCENTRATE_003 \'97 Concentrate may still represent calculated dry amount\
The engine may explain required dry mass and then convert it to concentrate volume, but technological counting remains liquid.\
\
---\
\
## 9. Tincture behavior\
\
### TYPE: tincture\
\
#### Default profile\
- `behaviorType = tincture`\
- `introductionMode = as_tincture`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = hydroalcoholic`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = true` unless explicit rule says otherwise\
- `heatPolicy = no_heating`\
- `volatilityPolicy = minimize_open_exposure`\
- `filtrationPolicy = avoid_if_possible`\
\
### RULE_TINCTURE_001 \'97 Tincture reduces water ad\
Tincture volume is counted in liquid sum and reduces water added ad.\
\
### RULE_TINCTURE_002 \'97 Tincture is late-stage component\
By default tincture should be introduced near the end of preparation, not boiled or heated with main solvent.\
\
### RULE_TINCTURE_003 \'97 Tincture is not treated as solvent unless explicit\
Tincture may contribute liquid volume but is not the default main solvent.\
\
---\
\
## 10. Liquid extract behavior\
\
### TYPE: liquidExtract\
\
#### Default profile\
- `behaviorType = liquidExtract`\
- `introductionMode = as_liquid_extract`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = mixed or hydroalcoholic depending on reference`\
- `addAtEnd = true` by default unless overridden\
- `heatPolicy = no_heating` or `unknown` depending on reference\
- `filtrationPolicy = avoid_if_possible`\
\
### RULE_LIQ_EXT_001 \'97 Liquid extract reduces ad solvent\
Liquid extract volume must be included in liquid sum.\
\
### RULE_LIQ_EXT_002 \'97 Late addition preferred\
If no explicit opposing rule exists, liquid extract should not be assigned to early heating stage.\
\
---\
\
## 11. Dry extract behavior\
\
### TYPE: dryExtract\
\
#### Default profile\
- `behaviorType = dryExtract`\
- `introductionMode = direct_dissolve` or `requires_separate_dissolution` depending on reference\
- `countsAsLiquid = false`\
- `countsAsSolid = true`\
- `affectsAd = false`\
- `affectsKvo = true` if relevant\
- `phaseType = unknown`\
\
### RULE_DRY_EXT_001 \'97 Dry extract behaves as solid\
Unless explicit liquid profile exists, dry extract is counted as dry substance.\
\
---\
\
## 12. Syrup behavior\
\
### TYPE: syrup\
\
#### Default profile\
- `behaviorType = syrup`\
- `introductionMode = as_syrup`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = aqueous`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = true` or late-middle stage depending on policy\
- `heatPolicy = mild_heating_only` only if syrup itself is being prepared, otherwise not relevant\
\
### RULE_SYRUP_001 \'97 Syrup reduces water ad\
Syrup volume contributes to liquid sum.\
\
### RULE_SYRUP_002 \'97 Syrup is not a dry solid branch\
Do not treat syrup as solids even if it contains dissolved sugar.\
\
---\
\
## 13. Aromatic water behavior\
\
### TYPE: aromaticWater\
\
#### Default profile\
- `behaviorType = aromaticWater`\
- `introductionMode = as_aromatic_water`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true` if fixed volume\
- `affectsKvo = false`\
- `phaseType = aqueous`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = true` if volatility/odor preservation matters\
- `heatPolicy = no_heating`\
- `volatilityPolicy = minimize_open_exposure`\
\
### RULE_AROM_WATER_001 \'97 Aromatic water counts as liquid\
It reduces the amount of water ad if present as fixed-volume component.\
\
### RULE_AROM_WATER_002 \'97 Aromatic water is not ordinary purified water\
It should not be silently merged with purified water identity in logic.\
\
### RULE_AROM_WATER_003 \'97 Heat caution\
Do not assign heating by default where aromatic fraction preservation matters.\
\
---\
\
## 14. Alcohol behavior\
\
### TYPE: alcohol\
\
#### Default profile\
- `behaviorType = alcohol`\
- `introductionMode = as_non_aqueous_solvent`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true` if fixed volume\
- `affectsKvo = false`\
- `phaseType = alcoholic`\
- `requiresSeparateDissolution = false`\
- `addAtEnd = false`\
- `heatPolicy = no_heating`\
- `volatilityPolicy = minimize_open_exposure`\
- `filtrationPolicy = avoid_if_possible`\
\
### RULE_ALCOHOL_001 \'97 Alcohol branch detection\
If alcohol is the main solvent, solution should enter non-aqueous or mixed-solvent branch.\
\
### RULE_ALCOHOL_002 \'97 No default heating\
Alcohol-containing systems should not receive heating instructions by default.\
\
---\
\
## 15. Glycerin behavior\
\
### TYPE: glycerin\
\
#### Default profile\
- `behaviorType = glycerin`\
- `introductionMode = as_non_aqueous_solvent`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = glycerinic`\
- `requiresSeparateDissolution = possible`\
- `heatPolicy = mild_heating_only` if technology allows\
- `volatilityPolicy = none`\
\
### RULE_GLYCERIN_001 \'97 Glycerin enters non-aqueous or mixed branch\
It must not be treated as ordinary purified water.\
\
### RULE_GLYCERIN_002 \'97 Density-capable calculations may be required\
If mass conversion is needed, density-aware calculation may be used.\
\
---\
\
## 16. Oil behavior\
\
### TYPE: oil\
\
#### Default profile\
- `behaviorType = oil`\
- `introductionMode = as_non_aqueous_solvent`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = oily`\
- `requiresSeparateDissolution = possible`\
- `heatPolicy = mild_heating_only` if reference allows\
- `filtrationPolicy = avoid_if_possible`\
\
### RULE_OIL_001 \'97 Oil enters oily/non-aqueous branch\
Oil must not be silently treated as aqueous liquid.\
\
### RULE_OIL_002 \'97 Compatibility check required\
If mixed with water without appropriate emulsifying logic, warn about phase incompatibility.\
\
---\
\
## 17. Volatile solvent behavior\
\
### TYPE: volatileSolvent\
\
Examples:\
- ether\
- chloroform\
- highly volatile alcohol-containing systems\
\
#### Default profile\
- `behaviorType = volatileSolvent`\
- `introductionMode = as_non_aqueous_solvent`\
- `countsAsLiquid = true`\
- `countsAsSolid = false`\
- `affectsAd = true`\
- `affectsKvo = false`\
- `phaseType = volatileOrganic`\
- `addAtEnd = true` when appropriate\
- `heatPolicy = no_heating`\
- `volatilityPolicy = add_last`\
- `filtrationPolicy = avoid_if_possible`\
\
### RULE_VOL_001 \'97 Volatile solvent protection\
Do not assign default heating or prolonged open manipulation.\
\
### RULE_VOL_002 \'97 Late addition preference\
If compatible with technology, volatile solvent should be introduced as late as possible.\
\
---\
\
## 18. Behavior interactions\
\
### RULE_INTERACT_001 \'97 Ready solution + ad\
Ready solution volume reduces ad solvent but does not enter solid branch.\
\
### RULE_INTERACT_002 \'97 Concentrate + dry solid mixed case\
If recipe contains both concentrates and dry solids:\
- concentrates count as liquids\
- dry solids count as solids\
- KVO applies only to valid dry-solid part\
- final water is calculated after all counted contributions\
\
### RULE_INTERACT_003 \'97 Tincture + aromatic water + syrup\
All three count as liquids.\
None of them should be silently merged into purified water identity.\
\
### RULE_INTERACT_004 \'97 Main solvent priority\
A component may count as liquid without being the primary solvent.\
The engine must distinguish:\
- liquid contributor\
- primary solvent\
- final ad solvent\
\
---\
\
## 19. Behavior-driven technology rules\
\
### RULE_TECH_BEHAVIOR_001 \'97 Technology from behavior, not only from name\
Technology steps must be generated from behavior profile.\
Ingredient name alone is insufficient.\
\
### RULE_TECH_BEHAVIOR_002 \'97 Separate dissolution stage\
If `requiresSeparateDissolution = true`, create an explicit preliminary stage in technology.\
\
### RULE_TECH_BEHAVIOR_003 \'97 Add-at-end stage\
If `addAtEnd = true`, ingredient must appear in a late technology step.\
\
### RULE_TECH_BEHAVIOR_004 \'97 Heating restriction propagation\
If any ingredient has:\
- `heatPolicy = no_heating`\
or\
- `add_after_cooling`\
\
the final technology plan must respect this.\
\
### RULE_TECH_BEHAVIOR_005 \'97 Filtration restriction propagation\
If ingredient profile says filtration should be avoided, do not insert routine filtration without warning.\
\
---\
\
## 20. Minimal default mapping table\
\
### Purified water\
- liquid\
- aqueous\
- ad-capable\
- not KVO\
- normal solvent\
\
### Dry substance\
- solid\
- may affect KVO\
- may require separate dissolution\
- may block true-solution path if insoluble\
\
### Ready solution\
- liquid\
- affects ad\
- no KVO\
- no solid branch\
\
### Standard solution\
- liquid\
- affects ad\
- no KVO\
- special-case only if explicit\
\
### Concentrate\
- liquid\
- affects ad\
- no KVO\
- calculated from required dry mass but introduced as liquid\
\
### Tincture\
- liquid\
- affects ad\
- hydroalcoholic\
- add late\
- no heating\
\
### Liquid extract\
- liquid\
- affects ad\
- often add late\
- no default heating\
\
### Dry extract\
- solid\
- possible KVO branch\
- may require separate dissolution\
\
### Syrup\
- liquid\
- affects ad\
- not solids\
\
### Aromatic water\
- liquid\
- affects ad\
- not same as purified water\
- avoid heating\
\
### Alcohol\
- liquid\
- non-aqueous solvent\
- no heating\
- volatility caution\
\
### Glycerin\
- liquid\
- non-aqueous / mixed solvent\
- density-aware branch may be needed\
\
### Oil\
- liquid\
- oily branch\
- compatibility checks with water required\
\
### Volatile solvent\
- liquid\
- no heating\
- add late if possible\
- avoid filtration if possible\
\
---\
\
## 21. Critical warnings the behavior layer must emit\
\
Possible warnings:\
- `missing_behavior_profile`\
- `ingredient_form_conflict`\
- `solution_treated_as_solid`\
- `kvo_applied_to_ready_solution`\
- `fixed_water_vs_ad_conflict`\
- `multiple_ad_conflict`\
- `target_inferred_by_fallback`\
- `incompatible_solvent_phases`\
- `requires_separate_dissolution_unhandled`\
- `late_addition_required`\
- `no_heating_required`\
- `filtration_policy_conflict`\
- `route_restriction_unhandled`\
\
---\
\
## 22. Final rule\
\
### RULE_BEHAVIOR_FINAL_001\
No solution calculation should be considered complete unless every ingredient has passed through:\
1. identity normalization\
2. behavior profile assignment\
3. role classification\
4. branch validation\
\
Only after that may the engine:\
- calculate mass\
- calculate concentrate volume\
- calculate ad solvent\
- apply KVO\
- generate technology\
- generate PPC}