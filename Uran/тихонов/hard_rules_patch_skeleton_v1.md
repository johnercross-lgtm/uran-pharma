# Hard Rules Patch Skeleton v1

Source: `validated_rules_v1.json`
Generated at UTC: `2026-03-07T16:23:35.008855+00:00`
Hard rules: **15**
Skeleton records: **30**

## BaseTechnologyBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift`

- `cand_00036` | `warning_candidate` | `dissolution` | `generic_rule`
  Rule: Серу осторожно, но тщательно растирают в подогретой ступке, добавляют часть (50,0—60,0 г) основы и диспергируют.
  TODO:
  - Добавить интеграцию `HR-cand_00036` в целевой блок.
  - Добавить идентификатор `HR-cand_00036` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00036`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift
@@
+        // TODO(Tikhonov cand_00036): Серу осторожно, но тщательно растирают в подогретой ступке, добавляют часть (50,0—60,0 г) основы и диспергируют.
+        // integration_kind: generic_rule
  ```

- `cand_00004` | `info_candidate` | `dissolution` | `generic_rule`
  Rule: Вследствие большой вязкости растворение в нем лекарственных веществ при комнатной температуре происходит медленно, поэтому его следует производить при нагревании на водяной бане до температуры 40—60 °С.
  TODO:
  - Добавить интеграцию `HR-cand_00004` в целевой блок.
  - Добавить идентификатор `HR-cand_00004` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00004`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift
@@
+        // TODO(Tikhonov cand_00004): Вследствие большой вязкости растворение в нем лекарственных веществ при комнатной температуре происходит медленно, поэтому его следует производить при нагревании на водяной бане до
+        // integration_kind: generic_rule
  ```

- `cand_00005` | `info_candidate` | `dissolution` | `generic_rule`
  Rule: Растворение лекарственных веществ в них, как и в глицерине, следует производить при нагревании на водяной бане.
  TODO:
  - Добавить интеграцию `HR-cand_00005` в целевой блок.
  - Добавить идентификатор `HR-cand_00005` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00005`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift
@@
+        // TODO(Tikhonov cand_00005): Растворение лекарственных веществ в них, как и в глицерине, следует производить при нагревании на водяной бане.
+        // integration_kind: generic_rule
  ```

- `cand_00013` | `info_candidate` | `sterility` | `generic_rule`
  Rule: Лекарства с антибиотиками отпускают в стерильной посуде, максимально исключающей попадание микрофлоры, оформляют этикетками «Приготовлено асептически», «Хранить в прохладном месте».
  TODO:
  - Добавить интеграцию `HR-cand_00013` в целевой блок.
  - Добавить идентификатор `HR-cand_00013` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00013`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift
@@
+        // TODO(Tikhonov cand_00013): Лекарства с антибиотиками отпускают в стерильной посуде, максимально исключающей попадание микрофлоры, оформляют этикетками «Приготовлено асептически», «Хранить в прохладном месте»
+        // integration_kind: generic_rule
  ```

- `cand_00014` | `info_candidate` | `sterility` | `generic_rule`
  Rule: Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдерживают воздействие высокой температуры — должны подвергаться стерилизации.
  TODO:
  - Добавить интеграцию `HR-cand_00014` в целевой блок.
  - Добавить идентификатор `HR-cand_00014` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00014`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift
@@
+        // TODO(Tikhonov cand_00014): Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдер
+        // integration_kind: generic_rule
  ```

## InfusionDecoctionBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/InfusionDecoctionBlock.swift`

- `cand_00027` | `info_candidate` | `safety_incompatibility` | `form_rule`
  Rule: Отвары из данной группы сырья немедленно процеживают после снятия инфундирки с водяной бани, так как дубильные вещества хорошо растворимы в горячей воде, а при охлаждении выпадают в виде хлопьевидного осадка.
  TODO:
  - Добавить form-specific предикат `HR-cand_00027` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00027` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00027`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/InfusionDecoctionBlock.swift
@@
+        // TODO(Tikhonov cand_00027): Отвары из данной группы сырья немедленно процеживают после снятия инфундирки с водяной бани, так как дубильные вещества хорошо растворимы в горячей воде, а при охлаждении выпадают 
+        // integration_kind: form_rule
  ```

- `cand_00021` | `info_candidate` | `heating` | `form_rule`
  Rule: По истечении указанного выше времени инфундирку снимают с водяной бани и охлаждают при комнатной температуре ( настои – 45, отвары – 10 минут ), после чего процеживают в мерный цилиндр ( при помощи пресс-цидилки ) через двойной слой марли и ватный тампон в устье воронки, отжимают остаток растительного материала и добавляют воду ( через тот же растительный материал ) до предписанного объёма вытяжки.
  TODO:
  - Добавить form-specific предикат `HR-cand_00021` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00021` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00021`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/InfusionDecoctionBlock.swift
@@
+        // TODO(Tikhonov cand_00021): По истечении указанного выше времени инфундирку снимают с водяной бани и охлаждают при комнатной температуре ( настои – 45, отвары – 10 минут ), после чего процеживают в мерный цил
+        // integration_kind: form_rule
  ```

## NonAqueousSolutionsBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift`

- `cand_00170` | `blocking_candidate` | `safety_incompatibility` | `route_rule`
  Rule: Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00170` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бе..."
  - Добавить идентификатор `HR-cand_00170` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00170`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00170): Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
+        // integration_kind: route_rule
  ```

- `cand_00223` | `warning_candidate` | `heating` | `route_rule`
  Rule: Нагревать хлороформ при растворении парафина необходимо очень осторожно, неплотно прикрыв склянку, чтобы не произошло разрыва флакона.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00223` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Нагревать хлороформ при растворении парафина необходимо очень осторожно, неплотно прикрыв ..."
  - Добавить идентификатор `HR-cand_00223` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00223`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00223): Нагревать хлороформ при растворении парафина необходимо очень осторожно, неплотно прикрыв склянку, чтобы не произошло разрыва флакона.
+        // integration_kind: route_rule
  ```

- `cand_00016` | `info_candidate` | `dissolution` | `route_rule`
  Rule: В сухую склянку для отпуска из темного стекла помещают 2,0 г ментола, тарируют и отвешивают 80,0 г подсолнечного масла, растворяют (можно при нагревании на теплой водяной бане).
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00016` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "В сухую склянку для отпуска из темного стекла помещают 2,0 г ментола, тарируют и отвешиваю..."
  - Добавить идентификатор `HR-cand_00016` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00016`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00016): В сухую склянку для отпуска из темного стекла помещают 2,0 г ментола, тарируют и отвешивают 80,0 г подсолнечного масла, растворяют (можно при нагревании на теплой водяной бане).
+        // integration_kind: route_rule
  ```

- `cand_00018` | `info_candidate` | `dissolution` | `route_rule`
  Rule: В фарфоровую чашку отвешивают 20,0 г касторового масла и растворяют в нем 1,0 г камфоры, можно при нагревании (до 40 °С) на водяной бане.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00018` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "В фарфоровую чашку отвешивают 20,0 г касторового масла и растворяют в нем 1,0 г камфоры, м..."
  - Добавить идентификатор `HR-cand_00018` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00018`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00018): В фарфоровую чашку отвешивают 20,0 г касторового масла и растворяют в нем 1,0 г камфоры, можно при нагревании (до 40 °С) на водяной бане.
+        // integration_kind: route_rule
  ```

## OintmentsBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/OintmentsBlock.swift`

- `cand_00036` | `warning_candidate` | `dissolution` | `form_rule`
  Rule: Серу осторожно, но тщательно растирают в подогретой ступке, добавляют часть (50,0—60,0 г) основы и диспергируют.
  TODO:
  - Добавить form-specific предикат `HR-cand_00036` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00036` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00036`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/OintmentsBlock.swift
@@
+        // TODO(Tikhonov cand_00036): Серу осторожно, но тщательно растирают в подогретой ступке, добавляют часть (50,0—60,0 г) основы и диспергируют.
+        // integration_kind: form_rule
  ```

- `cand_00019` | `info_candidate` | `dissolution` | `form_rule`
  Rule: Лекарственные вещества растворяют в расплавленной основе в фарфоровой чашке при осторожном нагревании на водяной бане.
  TODO:
  - Добавить form-specific предикат `HR-cand_00019` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00019` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00019`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/OintmentsBlock.swift
@@
+        // TODO(Tikhonov cand_00019): Лекарственные вещества растворяют в расплавленной основе в фарфоровой чашке при осторожном нагревании на водяной бане.
+        // integration_kind: form_rule
  ```

- `cand_00023` | `info_candidate` | `mixing_order` | `form_rule`
  Rule: Мазь для носа Колларгол (3,0г) растирают в ступке с водой (20 капель) и оставляют на несколько минут, потом добавляют ланолин водный (2,0г) и перемешивают до поглощения раствора, после чего добавляют вазелин и смешивают до однородности.
  TODO:
  - Добавить form-specific предикат `HR-cand_00023` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00023` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00023`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/OintmentsBlock.swift
@@
+        // TODO(Tikhonov cand_00023): Мазь для носа Колларгол (3,0г) растирают в ступке с водой (20 капель) и оставляют на несколько минут, потом добавляют ланолин водный (2,0г) и перемешивают до поглощения раствора, п
+        // integration_kind: form_rule
  ```

## PowdersTriturationsBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/PowdersTriturationsBlock.swift`

- `cand_00014` | `info_candidate` | `sterility` | `form_rule`
  Rule: Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдерживают воздействие высокой температуры — должны подвергаться стерилизации.
  TODO:
  - Добавить form-specific предикат `HR-cand_00014` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00014` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00014`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/PowdersTriturationsBlock.swift
@@
+        // TODO(Tikhonov cand_00014): Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдер
+        // integration_kind: form_rule
  ```

## PpkRenderer

Target file: `/Users/eugentamara/URAN/Uran/PpkRenderer.swift`

- `cand_00013` | `info_candidate` | `sterility` | `generic_rule`
  Rule: Лекарства с антибиотиками отпускают в стерильной посуде, максимально исключающей попадание микрофлоры, оформляют этикетками «Приготовлено асептически», «Хранить в прохладном месте».
  TODO:
  - Добавить интеграцию `HR-cand_00013` в целевой блок.
  - Добавить идентификатор `HR-cand_00013` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00013`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/PpkRenderer.swift
@@
+        // TODO(Tikhonov cand_00013): Лекарства с антибиотиками отпускают в стерильной посуде, максимально исключающей попадание микрофлоры, оформляют этикетками «Приготовлено асептически», «Хранить в прохладном месте»
+        // integration_kind: generic_rule
  ```

- `cand_00014` | `info_candidate` | `sterility` | `generic_rule`
  Rule: Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдерживают воздействие высокой температуры — должны подвергаться стерилизации.
  TODO:
  - Добавить интеграцию `HR-cand_00014` в целевой блок.
  - Добавить идентификатор `HR-cand_00014` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00014`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/PpkRenderer.swift
@@
+        // TODO(Tikhonov cand_00014): Присыпки, применяемые для нанесения на раны, поврежденную кожу или слизистые оболочки, а также порошки для новорожденных должны готовиться в асептических условиях, а если они выдер
+        // integration_kind: generic_rule
  ```

## SubstancePropertyCatalog

Target file: `/Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift`

- `cand_00170` | `blocking_candidate` | `safety_incompatibility` | `catalog_rule`
  Rule: Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00170`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00170` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00170`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00170): Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
+        // integration_kind: catalog_rule
  ```

- `cand_00079` | `warning_candidate` | `mixing_order` | `catalog_rule`
  Rule: Если калия перманганат прописан в виде концентрированного раствора (3, 4, 5 %), то для ускорения растворения его осторожно растирают в ступке с частью теплой процеженной очищенной воды, а затем добавляют остальное количество растворителя.
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00079`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00079` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00079`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00079): Если калия перманганат прописан в виде концентрированного раствора (3, 4, 5 %), то для ускорения растворения его осторожно растирают в ступке с частью теплой процеженной очищенной 
+        // integration_kind: catalog_rule
  ```

- `cand_00223` | `warning_candidate` | `heating` | `catalog_rule`
  Rule: Нагревать хлороформ при растворении парафина необходимо очень осторожно, неплотно прикрыв склянку, чтобы не произошло разрыва флакона.
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00223`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00223` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00223`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00223): Нагревать хлороформ при растворении парафина необходимо очень осторожно, неплотно прикрыв склянку, чтобы не произошло разрыва флакона.
+        // integration_kind: catalog_rule
  ```

- `cand_00016` | `info_candidate` | `dissolution` | `catalog_rule`
  Rule: В сухую склянку для отпуска из темного стекла помещают 2,0 г ментола, тарируют и отвешивают 80,0 г подсолнечного масла, растворяют (можно при нагревании на теплой водяной бане).
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00016`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00016` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00016`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00016): В сухую склянку для отпуска из темного стекла помещают 2,0 г ментола, тарируют и отвешивают 80,0 г подсолнечного масла, растворяют (можно при нагревании на теплой водяной бане).
+        // integration_kind: catalog_rule
  ```

- `cand_00018` | `info_candidate` | `dissolution` | `catalog_rule`
  Rule: В фарфоровую чашку отвешивают 20,0 г касторового масла и растворяют в нем 1,0 г камфоры, можно при нагревании (до 40 °С) на водяной бане.
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00018`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00018` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00018`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00018): В фарфоровую чашку отвешивают 20,0 г касторового масла и растворяют в нем 1,0 г камфоры, можно при нагревании (до 40 °С) на водяной бане.
+        // integration_kind: catalog_rule
  ```

- `cand_00032` | `info_candidate` | `dissolution` | `catalog_rule`
  Rule: В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
  TODO:
  - Добавить/обновить aliases + technologyRules/interactionRules для `HR-cand_00032`.
  - Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.
  - Добавить идентификатор `HR-cand_00032` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00032`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift
@@
+        // TODO(Tikhonov cand_00032): В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
+        // integration_kind: catalog_rule
  ```

## SuppositoriesBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/SuppositoriesBlock.swift`

- `cand_00019` | `info_candidate` | `dissolution` | `form_rule`
  Rule: Лекарственные вещества растворяют в расплавленной основе в фарфоровой чашке при осторожном нагревании на водяной бане.
  TODO:
  - Добавить form-specific предикат `HR-cand_00019` в `apply(context:)`.
  - Сгенерировать технологический шаг и/или предупреждение в PPK секциях.
  - Добавить идентификатор `HR-cand_00019` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00019`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/SuppositoriesBlock.swift
@@
+        // TODO(Tikhonov cand_00019): Лекарственные вещества растворяют в расплавленной основе в фарфоровой чашке при осторожном нагревании на водяной бане.
+        // integration_kind: form_rule
  ```

## VMSColloidsBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/VMSColloidsBlock.swift`

- `cand_00032` | `info_candidate` | `dissolution` | `generic_rule`
  Rule: В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
  TODO:
  - Добавить интеграцию `HR-cand_00032` в целевой блок.
  - Добавить идентификатор `HR-cand_00032` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00032`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/VMSColloidsBlock.swift
@@
+        // TODO(Tikhonov cand_00032): В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
+        // integration_kind: generic_rule
  ```

## WaterSolutionsBlock

Target file: `/Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift`

- `cand_00170` | `blocking_candidate` | `safety_incompatibility` | `route_rule`
  Rule: Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00170` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бе..."
  - Добавить идентификатор `HR-cand_00170` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00170`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00170): Следует учитывать, что твины и спены несовместимы с салицилатами, производными параокси-бензойной кислоты, фенолами и т.
+        // integration_kind: route_rule
  ```

- `cand_00079` | `warning_candidate` | `mixing_order` | `route_rule`
  Rule: Если калия перманганат прописан в виде концентрированного раствора (3, 4, 5 %), то для ускорения растворения его осторожно растирают в ступке с частью теплой процеженной очищенной воды, а затем добавляют остальное количество растворителя.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00079` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Если калия перманганат прописан в виде концентрированного раствора (3, 4, 5 %), то для уск..."
  - Добавить идентификатор `HR-cand_00079` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00079`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00079): Если калия перманганат прописан в виде концентрированного раствора (3, 4, 5 %), то для ускорения растворения его осторожно растирают в ступке с частью теплой процеженной очищенной 
+        // integration_kind: route_rule
  ```

- `cand_00027` | `info_candidate` | `safety_incompatibility` | `route_rule`
  Rule: Отвары из данной группы сырья немедленно процеживают после снятия инфундирки с водяной бани, так как дубильные вещества хорошо растворимы в горячей воде, а при охлаждении выпадают в виде хлопьевидного осадка.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00027` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Отвары из данной группы сырья немедленно процеживают после снятия инфундирки с водяной бан..."
  - Добавить идентификатор `HR-cand_00027` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00027`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00027): Отвары из данной группы сырья немедленно процеживают после снятия инфундирки с водяной бани, так как дубильные вещества хорошо растворимы в горячей воде, а при охлаждении выпадают 
+        // integration_kind: route_rule
  ```

- `cand_00023` | `info_candidate` | `mixing_order` | `route_rule`
  Rule: Мазь для носа Колларгол (3,0г) растирают в ступке с водой (20 капель) и оставляют на несколько минут, потом добавляют ланолин водный (2,0г) и перемешивают до поглощения раствора, после чего добавляют вазелин и смешивают до однородности.
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00023` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "Мазь для носа Колларгол (3,0г) растирают в ступке с водой (20 капель) и оставляют на неско..."
  - Добавить идентификатор `HR-cand_00023` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00023`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00023): Мазь для носа Колларгол (3,0г) растирают в ступке с водой (20 капель) и оставляют на несколько минут, потом добавляют ланолин водный (2,0г) и перемешивают до поглощения раствора, п
+        // integration_kind: route_rule
  ```

- `cand_00032` | `info_candidate` | `dissolution` | `route_rule`
  Rule: В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
  TODO:
  - В `apply(context:)` добавить ветку-правило `HR-cand_00032` с предикатом по составу/растворителю.
  - При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.
  - Проверить конфликт с существующими правилами блока для: "В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его раств..."
  - Добавить идентификатор `HR-cand_00032` в локальный список hard-rules блока.
  - Добавить unit-тест/fixture на срабатывание `HR-cand_00032`.
  Patch skeleton:
  ```diff
*** Update File: /Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift
@@
+        // TODO(Tikhonov cand_00032): В данном случае в ступке растирают протаргол с 6—8 каплями глицерина, после чего его растворяют в воде (0,9 мл).
+        // integration_kind: route_rule
  ```
