This archive was cleaned from the uploaded package.

What was removed:
- __MACOSX/
- .DS_Store
- all AppleDouble files (._*)
- the entire extemp_reference_200/ folder from the uploaded archive because its *.json files were actually RTF files renamed to .json and were not safe for Codex ingestion.
- extra file сказать.rtf

What was preserved:
- CODEX prompts
- reference/extemp_reference_200.csv
- reference/parsed/*.json
- reference/PHARM_ENGINE_STATE_MACHINE.md
- solutions_spec/*
- validation_report.json

Important:
If you still want NORMALIZATION_DICTIONARY.json, REFERENCE_PRIORITY_POLICY.json, MANUAL_OVERRIDE_LAYER.json, ENGINE_DECISION_LOG_SCHEMA.json, REGEX_NORMALIZATION_PATTERNS.json, and RECIPE_BREAKER_TEST_SET.json included as machine-readable JSON, they must be saved again as real UTF-8 JSON files, not RTF.
