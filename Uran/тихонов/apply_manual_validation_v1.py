#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


Decision = dict[str, Any]


DECISIONS: dict[str, Decision] = {
    "cand_00048": {"status": "rejected", "mode": None, "notes": "SOP по режиму асептического блока, не правило Rx-прописи."},
    "cand_00049": {"status": "rejected", "mode": None, "notes": "Ограничение на объём стерилизации относится к производственной инфраструктуре."},
    "cand_00088": {"status": "rejected", "mode": None, "notes": "Правило эксплуатации оборудования, не логика расчёта/технологии прописи."},
    "cand_00170": {"status": "approved", "mode": "hard_rule", "notes": "Технологическая несовместимость ПАВ/фенолов/салицилатов релевантна движку как предупреждение."},
    "cand_00166": {"status": "rejected", "mode": None, "notes": "SOP по гирям и взвешиванию, не правило построения техплана."},
    "cand_00167": {"status": "rejected", "mode": None, "notes": "Организация помещения, не уровень RxEngine."},
    "cand_00169": {"status": "rejected", "mode": None, "notes": "Нишевое правило по санобработке, не к рецептурной технологии движка."},
    "cand_00171": {"status": "rejected", "mode": None, "notes": "Организационное правило асептического блока."},
    "cand_00172": {"status": "rejected", "mode": None, "notes": "Организационное правило хранения, вне RxEngine."},
    "cand_00036": {"status": "approved", "mode": "hard_rule", "notes": "Полезное правило диспергирования серы для мазевых/пастообразных систем."},
    "cand_00079": {"status": "approved", "mode": "hard_rule", "notes": "Практически применимое правило для концентрированных растворов KMnO4."},
    "cand_00276": {"status": "approved", "mode": "hint_only", "notes": "Общее экспертное ограничение по эмульгаторам; лучше как поясняющее предупреждение."},
    "cand_00222": {"status": "approved", "mode": "hint_only", "notes": "Температурное ограничение полезно, но без контекста формы лучше как hint."},
    "cand_00223": {"status": "approved", "mode": "hard_rule", "notes": "Конкретный safety-паттерн для chloroform/paraffin в неводных растворах."},
    "cand_00001": {"status": "approved", "mode": "hint_only", "notes": "Специфичный пример асептического изготовления; оставить как технологический паттерн."},
    "cand_00003": {"status": "approved", "mode": "hint_only", "notes": "Рецептурно-специфичный кейс, но полезен как иллюстрация порядка внесения."},
    "cand_00002": {"status": "approved", "mode": "hint_only", "notes": "Полезный порядок растворения в глицерине, но состав частный."},
    "cand_00006": {"status": "rejected", "mode": None, "notes": "Частная пропись для вдуваний, слабая переносимость в общий движок."},
    "cand_00007": {"status": "approved", "mode": "hint_only", "notes": "Асеptic-паттерн для антибиотических растворов."},
    "cand_00008": {"status": "rejected", "mode": None, "notes": "Общее описание требований к производству, слишком широкий уровень."},
    "cand_00004": {"status": "approved", "mode": "hard_rule", "notes": "Явное правило: вязкие растворители -> водяная баня 40-60°C."},
    "cand_00005": {"status": "approved", "mode": "hard_rule", "notes": "Подтверждение правила нагрева для вязких неводных сред."},
    "cand_00011": {"status": "approved", "mode": "hint_only", "notes": "Частный антибиотический кейс в масле, применять как справочную подсказку."},
    "cand_00012": {"status": "rejected", "mode": None, "notes": "Правило для ЛПУ/разлива, вне контекста аптеки RxEngine."},
    "cand_00013": {"status": "approved", "mode": "hard_rule", "notes": "Маркировка и хранение антибиотических асептических форм релевантны выходу движка."},
    "cand_00014": {"status": "approved", "mode": "hard_rule", "notes": "Ключевое правило: порошки на раны/слизистые/новорождённым требуют асептики/стерилизации."},
    "cand_00009": {"status": "approved", "mode": "hint_only", "notes": "Практический приём по растворению через пасту; как технологическая подсказка."},
    "cand_00010": {"status": "rejected", "mode": None, "notes": "Слишком узкая последовательность для конкретной прописи."},
    "cand_00027": {"status": "approved", "mode": "hard_rule", "notes": "Важное правило для настоев/отваров с дубильными веществами (горячее процеживание)."},
    "cand_00028": {"status": "rejected", "mode": None, "notes": "Локальное исключение по работе с тарой, не ядро движка."},
    "cand_00029": {"status": "approved", "mode": "hint_only", "notes": "Частный офтальмологический кейс эмульгирования, использовать как guidance."},
    "cand_00030": {"status": "approved", "mode": "hint_only", "notes": "Специфичный кейс суппозиториев с антибиотиком, применим как подсказка."},
    "cand_00015": {"status": "rejected", "mode": None, "notes": "Гомеопатический контекст не является текущей целевой веткой RxEngine."},
    "cand_00016": {"status": "approved", "mode": "hard_rule", "notes": "Растворение ментола в масле при мягком нагреве — устойчивый неводный паттерн."},
    "cand_00017": {"status": "approved", "mode": "hint_only", "notes": "Сложная частная композиция; полезно как порядок операций, не как жёсткое правило."},
    "cand_00018": {"status": "approved", "mode": "hard_rule", "notes": "Растворение камфоры в маслах с ограничением температуры."},
    "cand_00019": {"status": "approved", "mode": "hard_rule", "notes": "Общее правило: растворение в расплавленной основе при осторожном нагреве."},
    "cand_00021": {"status": "approved", "mode": "hard_rule", "notes": "Целевой технологический протокол инфузов/декоктов (охлаждение, фильтрация, доведение до объёма)."},
    "cand_00020": {"status": "rejected", "mode": None, "notes": "Перечень операций без предикатов и условий применения."},
    "cand_00022": {"status": "approved", "mode": "hint_only", "notes": "Частная последовательность для серы/стрептоцида, оставить как иллюстративный паттерн."},
    "cand_00023": {"status": "approved", "mode": "hard_rule", "notes": "Полезный паттерн для коллоидов в мазях: предварительное набухание/раствор + эмульсионная база."},
    "cand_00024": {"status": "approved", "mode": "hint_only", "notes": "Технология затирания пор и циклов растирания; как SOP-подсказка."},
    "cand_00025": {"status": "approved", "mode": "hint_only", "notes": "Частный пример левигации/декантации, как guidance для суспензий."},
    "cand_00026": {"status": "rejected", "mode": None, "notes": "Фрагмент обрезан overlap-ом, низкое качество источника."},
    "cand_00032": {"status": "approved", "mode": "hard_rule", "notes": "Классическое правило для протаргола: предварительное растирание с глицерином, затем вода."},
    "cand_00044": {"status": "rejected", "mode": None, "notes": "Обрезанный контекст, не хватает условий для корректной формализации."},
    "cand_00050": {"status": "rejected", "mode": None, "notes": "Инъекционные формы и общая стерилизация — вне текущего контура модуля."},
    "cand_00051": {"status": "rejected", "mode": None, "notes": "Архитектура помещений, не логика RxEngine."},
    "cand_00052": {"status": "approved", "mode": "hint_only", "notes": "Полезный офтальмологический паттерн по асептике/изотоничности, но концентрации требуют доп.проверки."},
    "cand_00053": {"status": "approved", "mode": "hint_only", "notes": "Рецептурный асептический паттерн растворения антибиотика в изотонике."},
}


TARGET_OVERRIDES: dict[str, list[str]] = {
    "cand_00170": ["SubstancePropertyCatalog", "NonAqueousSolutionsBlock", "WaterSolutionsBlock"],
    "cand_00036": ["OintmentsBlock", "BaseTechnologyBlock"],
    "cand_00079": ["WaterSolutionsBlock", "SubstancePropertyCatalog"],
    "cand_00276": ["SubstancePropertyCatalog", "OintmentsBlock", "PpkRenderer"],
    "cand_00222": ["OintmentsBlock", "SuppositoriesBlock", "PpkRenderer"],
    "cand_00223": ["NonAqueousSolutionsBlock", "SubstancePropertyCatalog"],
    "cand_00013": ["BaseTechnologyBlock", "PpkRenderer"],
    "cand_00014": ["PowdersTriturationsBlock", "BaseTechnologyBlock", "PpkRenderer"],
    "cand_00027": ["InfusionDecoctionBlock", "WaterSolutionsBlock"],
    "cand_00016": ["NonAqueousSolutionsBlock", "SubstancePropertyCatalog"],
    "cand_00018": ["NonAqueousSolutionsBlock", "SubstancePropertyCatalog"],
    "cand_00019": ["OintmentsBlock", "SuppositoriesBlock"],
    "cand_00021": ["InfusionDecoctionBlock"],
    "cand_00023": ["OintmentsBlock", "WaterSolutionsBlock"],
    "cand_00032": ["VMSColloidsBlock", "WaterSolutionsBlock", "SubstancePropertyCatalog"],
    "cand_00052": ["OphthalmicDropsBlock", "DropsBlock", "PpkRenderer"],
}


def priority_for_mode(mode: str | None) -> str:
    if mode == "hard_rule":
        return "ready_for_formalization"
    if mode == "hint_only":
        return "add_as_contextual_guidance"
    return "do_not_integrate"


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply manual validation decisions for top-50 batch")
    parser.add_argument(
        "--input",
        default="engine_rule_validation_batch_top50.json",
        help="Input batch file",
    )
    parser.add_argument(
        "--output",
        default="validated_rules_v1.json",
        help="Output validated rules file",
    )
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    source = json.loads(input_path.read_text(encoding="utf-8"))
    records = source.get("records") or []

    validated: list[dict[str, Any]] = []
    missing: list[str] = []

    for record in records:
        candidate = record.get("candidate") or {}
        candidate_id = candidate.get("id")
        if candidate_id not in DECISIONS:
            missing.append(str(candidate_id))
            continue

        decision = DECISIONS[candidate_id]
        status = decision["status"]
        mode = decision["mode"]

        suggested_targets = record.get("engine_target_suggestion") or []
        final_targets = TARGET_OVERRIDES.get(candidate_id, suggested_targets if status == "approved" else [])

        validated_record = {
            "batch_rank": record.get("batch_rank"),
            "candidate_id": candidate_id,
            "validation_status": status,
            "integration_mode": mode,
            "integration_priority": priority_for_mode(mode),
            "engine_target_final": final_targets,
            "review_result": "ACCEPTED" if status == "approved" else "REJECTED",
            "reviewer_notes": decision["notes"],
            "requires_regression_tests": bool(status == "approved" and mode == "hard_rule"),
            "candidate": candidate,
        }
        validated.append(validated_record)

    if missing:
        raise RuntimeError(f"Missing manual decisions for candidate ids: {', '.join(missing)}")

    approved = [r for r in validated if r["validation_status"] == "approved"]
    rejected = [r for r in validated if r["validation_status"] == "rejected"]
    mode_counts = Counter(r["integration_mode"] or "none" for r in validated)
    category_counts = Counter((r["candidate"].get("category_primary") or "unknown") for r in approved)

    payload = {
        "metadata": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_batch_file": input_path.name,
            "version": "v1",
            "total_records": len(validated),
            "approved_count": len(approved),
            "rejected_count": len(rejected),
            "mode_counts": dict(mode_counts),
            "approved_category_counts": dict(category_counts),
        },
        "validated_records": validated,
        "approved_rules": [
            {
                "candidate_id": r["candidate_id"],
                "integration_mode": r["integration_mode"],
                "engine_target_final": r["engine_target_final"],
                "rule_text": r["candidate"].get("rule_text"),
                "category_primary": r["candidate"].get("category_primary"),
                "suggested_severity": ((r["candidate"].get("suggested") or {}).get("severity")),
            }
            for r in approved
        ],
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved validated set with {len(approved)} approved / {len(rejected)} rejected to {output_path}")


if __name__ == "__main__":
    main()
