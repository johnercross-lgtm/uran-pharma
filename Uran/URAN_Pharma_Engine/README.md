# extemp_reference_200 clean package

This archive contains a cleaned and normalized package derived from `extemp_reference_200.csv`.

## What's included
- `reference/parsed/extemp_reference_200_full_records.json` — full no-loss source mapping for every parsed row
- specialized parsed layers: `substances_master.json`, `dose_limits.json`, `physchem_reference.json`, `solution_reference.json`, `ointment_reference.json`, `herbal_reference.json`, `tincture_reference.json`, `extract_reference.json`
- added support layers: `safety_reference.json`, `substance_alias_table.json`, `raw_column_map.json`, `normalization_log.json`, `anomalies_report.json`
- `solutions_spec/` — clean JSON/MD files for the solutions engine, converted from the uploaded archive and stripped of RTF wrappers

## Important fixes applied
- Removed macOS junk: `__MACOSX`, `.DS_Store`, AppleDouble `._*`
- Converted `.json.rtf` files into real UTF-8 `.json`
- Removed duplicate `TEST_RECIPES_SOLUTIONS1.json`
- Realigned malformed source rows:
  - line 272 `Protargolum`
  - line 273 `Pepsinum`

## Integrity policy
No source columns were dropped from the full-record layer.
Typed/normalized layers preserve source trace through `__sourceMeta` and `__raw` fragments.
