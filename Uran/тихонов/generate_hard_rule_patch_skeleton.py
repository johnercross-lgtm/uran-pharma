#!/usr/bin/env python3
import argparse
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TARGET_FILE_MAP: dict[str, str] = {
    "SubstancePropertyCatalog": "/Users/eugentamara/URAN/Uran/SubstancePropertyCatalog.swift",
    "BaseTechnologyBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/BaseTechnologyBlock.swift",
    "WaterSolutionsBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/WaterSolutionsBlock.swift",
    "NonAqueousSolutionsBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/NonAqueousSolutionsBlock.swift",
    "InfusionDecoctionBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/InfusionDecoctionBlock.swift",
    "OintmentsBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/OintmentsBlock.swift",
    "PowdersTriturationsBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/PowdersTriturationsBlock.swift",
    "SuppositoriesBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/SuppositoriesBlock.swift",
    "VMSColloidsBlock": "/Users/eugentamara/URAN/Uran/RxEngine/Blocks/VMSColloidsBlock.swift",
    "PpkRenderer": "/Users/eugentamara/URAN/Uran/PpkRenderer.swift",
}


def integration_kind(target: str) -> str:
    if target == "SubstancePropertyCatalog":
        return "catalog_rule"
    if target in {"WaterSolutionsBlock", "NonAqueousSolutionsBlock"}:
        return "route_rule"
    if target in {"OintmentsBlock", "SuppositoriesBlock", "PowdersTriturationsBlock", "InfusionDecoctionBlock"}:
        return "form_rule"
    return "generic_rule"


def implementation_todo(target: str, rule_text: str, candidate_id: str) -> list[str]:
    prefix = f"HR-{candidate_id}"
    common = [
        f"Добавить идентификатор `{prefix}` в локальный список hard-rules блока.",
        f"Добавить unit-тест/fixture на срабатывание `{prefix}`.",
    ]

    if target == "SubstancePropertyCatalog":
        return [
            f"Добавить/обновить aliases + technologyRules/interactionRules для `{prefix}`.",
            "Привязать правило к конкретным веществам (латинские/русские алиасы) и типу несовместимости.",
            *common,
        ]
    if target in {"WaterSolutionsBlock", "NonAqueousSolutionsBlock"}:
        return [
            f"В `apply(context:)` добавить ветку-правило `{prefix}` с предикатом по составу/растворителю.",
            "При срабатывании формировать `context.addIssue(...)` и/или `context.addStep(...)`.",
            f"Проверить конфликт с существующими правилами блока для: \"{rule_text[:90]}...\"",
            *common,
        ]
    if target in {"OintmentsBlock", "SuppositoriesBlock", "PowdersTriturationsBlock", "InfusionDecoctionBlock"}:
        return [
            f"Добавить form-specific предикат `{prefix}` в `apply(context:)`.",
            "Сгенерировать технологический шаг и/или предупреждение в PPK секциях.",
            *common,
        ]
    return [
        f"Добавить интеграцию `{prefix}` в целевой блок.",
        *common,
    ]


def build_patch_hunk(target: str, rule: dict[str, Any]) -> str:
    candidate_id = rule["candidate_id"]
    text = rule["rule_text"].replace("\n", " ").strip()
    file_path = TARGET_FILE_MAP.get(target, f"/Users/eugentamara/URAN/Uran/{target}.swift")
    kind = integration_kind(target)
    note = f"// TODO(Tikhonov {candidate_id}): {text[:180]}"
    return "\n".join(
        [
            f"*** Update File: {file_path}",
            "@@",
            f"+        {note}",
            f"+        // integration_kind: {kind}",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate skeleton patch plan for approved hard rules")
    parser.add_argument(
        "--input",
        default="validated_rules_v1.json",
        help="Path to validated_rules_v1.json",
    )
    parser.add_argument(
        "--output-json",
        default="hard_rules_patch_skeleton_v1.json",
        help="Output JSON plan path",
    )
    parser.add_argument(
        "--output-md",
        default="hard_rules_patch_skeleton_v1.md",
        help="Output Markdown skeleton path",
    )
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_json = Path(args.output_json).expanduser().resolve()
    output_md = Path(args.output_md).expanduser().resolve()

    payload = json.loads(input_path.read_text(encoding="utf-8"))
    approved_rules = payload.get("approved_rules") or []
    hard_rules = [r for r in approved_rules if r.get("integration_mode") == "hard_rule"]

    plan_records: list[dict[str, Any]] = []
    by_target: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for idx, rule in enumerate(hard_rules, start=1):
        candidate_id = rule.get("candidate_id")
        targets = rule.get("engine_target_final") or []
        for target in targets:
            record = {
                "skeleton_id": f"sk_{idx:03d}_{target}",
                "candidate_id": candidate_id,
                "rule_text": rule.get("rule_text"),
                "category_primary": rule.get("category_primary"),
                "suggested_severity": rule.get("suggested_severity"),
                "target": target,
                "target_file": TARGET_FILE_MAP.get(target, f"/Users/eugentamara/URAN/Uran/{target}.swift"),
                "integration_kind": integration_kind(target),
                "todo": implementation_todo(target, rule.get("rule_text") or "", candidate_id or "unknown"),
                "patch_hunk_skeleton": build_patch_hunk(target, rule),
            }
            plan_records.append(record)
            by_target[target].append(record)

    json_payload = {
        "metadata": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_file": input_path.name,
            "hard_rules_count": len(hard_rules),
            "skeleton_records_count": len(plan_records),
            "targets": sorted(by_target.keys()),
        },
        "records": plan_records,
    }
    output_json.write_text(json.dumps(json_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    md_lines: list[str] = []
    md_lines.append("# Hard Rules Patch Skeleton v1")
    md_lines.append("")
    md_lines.append(f"Source: `{input_path.name}`")
    md_lines.append(f"Generated at UTC: `{json_payload['metadata']['generated_at_utc']}`")
    md_lines.append(f"Hard rules: **{len(hard_rules)}**")
    md_lines.append(f"Skeleton records: **{len(plan_records)}**")
    md_lines.append("")

    for target in sorted(by_target.keys()):
        records = by_target[target]
        target_file = TARGET_FILE_MAP.get(target, f"/Users/eugentamara/URAN/Uran/{target}.swift")
        md_lines.append(f"## {target}")
        md_lines.append("")
        md_lines.append(f"Target file: `{target_file}`")
        md_lines.append("")
        for rec in records:
            md_lines.append(
                f"- `{rec['candidate_id']}` | `{rec['suggested_severity']}` | `{rec['category_primary']}` | `{rec['integration_kind']}`"
            )
            md_lines.append(f"  Rule: {rec['rule_text']}")
            md_lines.append("  TODO:")
            for todo in rec["todo"]:
                md_lines.append(f"  - {todo}")
            md_lines.append("  Patch skeleton:")
            md_lines.append("  ```diff")
            md_lines.append(rec["patch_hunk_skeleton"])
            md_lines.append("  ```")
            md_lines.append("")

    output_md.write_text("\n".join(md_lines).rstrip() + "\n", encoding="utf-8")

    print(f"Saved JSON skeleton: {output_json}")
    print(f"Saved MD skeleton: {output_md}")


if __name__ == "__main__":
    main()
