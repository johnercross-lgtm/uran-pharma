# Solution Engine v1 Status

## Реализованные модули
- IngredientParser
- SubstanceResolver
- BehaviorProfileResolver
- SolutionBranchSelector
- SolutionCalculationEngine
- TechnologyPlanner
- ValidationEngine
- DoseValidator
- PackagingResolver
- PPKRenderer
- Оркестратор `SolutionEngine` c прохождением состояний S0..S15

## Поддерживаемые ветви (solutions only)
- `aqueous_true_solution`
- `aqueous_burette_solution`
- `ready_solution_mix`
- `standard_solution_mix`
- `non_aqueous_solution`
- `volatile_non_aqueous_solution`
- `special_dissolution_path`

## Заблокированные маршруты / режимы
- `injection`: блокируется в normal solution engine (`sterility_required_but_not_supported`, `unsupported_route_claimed_complete`).
- `inhalation`: блокируется при неподдержанной ветви (`branch_not_allowed_for_route`).
- `ophthalmic`: complete-результат блокируется без стерильного модуля (`sterility_required_but_not_supported`), также поднимаются `isotonicity_required_but_not_checked`, `ph_check_required_but_missing`.

## Известные ограничения v1
- Покрыт только класс `solution`; другие лекарственные формы не подключены.
- Нет стерильного технологического контура; поэтому sterile routes не маркируются как complete/exact.
- Нет полноценного расчёта изотоничности и pH-проверки (только warnings по route-policy).
- При `unresolved_substance` / `missing_behavior_profile` движок понижает confidence (`heuristic`) и не делает догадок.
- Все rule-конфликты и missing-rules возвращаются как warnings; reference-данные не изменяются автоматически.

## Миграция Water-блока в v1 (по шагам)
- Шаг 1 (сделано): перенесены ключевые валидации совместимости в `ValidationEngine`:
  - `solution.catalog.acidSensitive`
  - `solution.catalog.alkaliSensitive`
  - `solution.catalog.glycerinPhShift`
  - `solution.tweenspan.incompatibility`
  - `solution.hexamine.acidicRisk`
  - `solution.iodine.iodide.required`
  - `solution.iodine.iodide.ratio`
- Шаг 2 (сделано): в `TechnologyPlanner` добавлен водный подплан:
  - корректный порядок для йодной системы: сначала iodidum, затем Iodum, затем `ad V`;
  - режимы нагрева для водных растворов (теплая/горячая/кипящая вода) по растворимости и маркерам;
  - фильтрация только через стеклянный фильтр для соответствующих компонентов;
  - отдельные предупреждающие технологические операции для сильных окислителей и Argentum nitricum;
  - отдельная технологическая строка для Natrii hydrocarbonas (без интенсивного нагрева/взбалтывания).
- Шаг 3 (сделано, фаза A): выровнен рендер и терминология:
  - локализованы предупреждения и fallback-сообщения в `SolutionEngine`;
  - локализованы названия секций PPK при адаптации v1 -> legacy;
  - добавлена очистка повторной нумерации (`1. 1.` и подобные префиксы);
  - минимизированы англоязычные шаблоны шагов в `ModularRxOrchestrator`.
- Шаг 4 (сделано): устранены остаточные branch-конфликты для текстового ввода (`Sol. ... % - V ml`) и выровнена expected-логика breaker-кейсов `RB_001/RB_009/RB_045`:
  - нормализован парсинг строк с префиксом `Rp.:` (без паразитного лидирующего `.` в названии вещества);
  - скорректирован выбор `usesConcentrate` (только при явном solution-вводе), что вернуло KVO-путь для dry `ad`-кейсов;
  - для пары `Iodum + Kalii iodidum` восстановлен выбор ветки `special_dissolution_path`;
  - снят ложный блок `no_heating_component_conflict` для target-line в `aqueous_burette_solution`.
- Шаг 5 (сделано): зафиксирован strict snapshot-слой и добавлен единый breaker-гейт:
  - strict snapshots обновлены под текущую детерминированную логику `SolutionEngine`;
  - раннеры `run_solution_breaker_tests.swift` и `run_solution_breaker_snapshot_tests.swift` теперь завершаются с non-zero exit code при провале;
  - добавлен единый скрипт прогона `scripts/run_solution_breaker_gate.sh` (`--update-strict` + base breaker + strict snapshots).
- Шаг 6 (сделано): интегрирован CI-гейт для Solution Engine:
  - добавлен GitHub Actions workflow `.github/workflows/solution-engine-breaker-gate.yml`;
  - workflow запускает quality-гейт на `macos-14` для `push/pull_request` по релевантным путям и для `workflow_dispatch`.
- Шаг 7 (сделано): добавлен full quality gate, чтобы “всё работало стабильно”:
  - `scripts/run_solution_breaker_gate.sh` расширен режимом `--check-strict-sync` (проверка, что strict snapshots не устарели);
  - добавлен `scripts/run_solution_quality_gate.sh` (strict-sync + breaker + `xcodebuild`);
  - CI workflow переведён на запуск `run_solution_quality_gate.sh` (включая сборку iOS target без подписи).

## Сводка критических тестов
- Базовый breaker-набор: `RECIPE_BREAKER_TEST_SET.json`.
  - Текущий результат: `50/50 PASS`, `0 FAIL`.
- Строгий snapshot-слой: `RECIPE_BREAKER_STRICT_SNAPSHOTS.json`.
  - Текущий результат: `10/10 PASS`, `0 FAIL`.
  - Кейсы: `RB_001, RB_002, RB_020, RB_021, RB_026, RB_027, RB_028, RB_039, RB_042, RB_045`.
  - Проверяются: branch, route, confidence, state, warnings(code|state|severity), technology flags/steps, packaging/labels/storage, расчёты (water/solids/kvo/masses/concentrates), PPC section keys/line counts и отсутствие forbidden stock-QC phrase leakage.

## Где интегрировать в поток приложения
- Точка входа pipeline: `Uran/RxEngine/ModularRxOrchestrator.swift` в `ModularRxEngine.evaluate(draft:isNormalized:)`.
- Рекомендуемая вставка:
  1. После normalizer/analyzer и до block-routing.
  2. Только если effective form = solutions.
  3. Через adapter `ExtempRecipeDraft -> SolutionEngineRequest`.
  4. На первом этапе запускать в shadow-mode (сравнение с текущим блоковым пайплайном), затем switch по feature flag.
- Маршрутизацию на другие формы не расширять в v1.
