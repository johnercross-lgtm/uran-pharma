#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SEVERITY_RANK = {
    "blocking_candidate": 0,
    "warning_candidate": 1,
    "info_candidate": 2,
}

CATEGORY_PRIORITY = {
    "safety_incompatibility": 0,
    "sterility": 1,
    "dissolution": 2,
    "heating": 3,
    "filtration": 4,
    "mixing_order": 5,
    "volume_adjustment": 6,
    "trituration": 7,
    "quality_storage": 8,
}


def target_blocks_for(candidate: dict[str, Any]) -> list[str]:
    category = candidate.get("category_primary", "")
    applies_to = ((candidate.get("suggested") or {}).get("applies_to") or {})
    forms = set(applies_to.get("forms") or [])
    solvents = set(applies_to.get("solvents") or [])

    targets: list[str] = []

    if category == "safety_incompatibility":
        targets.extend(["SubstancePropertyCatalog", "NonAqueousSolutionsBlock", "WaterSolutionsBlock"])
    elif category == "sterility":
        if "drops" in forms:
            targets.extend(["OphthalmicDropsBlock", "DropsBlock"])
        if "ointments" in forms:
            targets.append("OintmentsBlock")
        targets.extend(["BaseTechnologyBlock", "PpkRenderer"])
    elif category in {"dissolution", "heating", "filtration", "mixing_order", "volume_adjustment"}:
        if solvents & {"ethanol", "glycerin", "oil", "ether", "chloroform"}:
            targets.append("NonAqueousSolutionsBlock")
        if forms & {"solutions", "drops", "infusions_decoctions"} or "water" in solvents:
            targets.append("WaterSolutionsBlock")
        if "infusions_decoctions" in forms:
            targets.append("InfusionDecoctionBlock")
        targets.append("BaseTechnologyBlock")
    elif category == "trituration":
        if "powders" in forms:
            targets.append("PowdersTriturationsBlock")
        if "ointments" in forms:
            targets.append("OintmentsBlock")
        targets.append("BaseTechnologyBlock")
    elif category == "quality_storage":
        targets.extend(["PpkRenderer", "BaseTechnologyBlock"])

    # Keep deterministic order and uniqueness
    unique: list[str] = []
    for target in targets:
        if target not in unique:
            unique.append(target)
    return unique or ["BaseTechnologyBlock"]


def review_priority_for(severity: str, score: int) -> str:
    if severity == "blocking_candidate":
        return "P0"
    if severity == "warning_candidate":
        return "P1"
    if score >= 9:
        return "P2"
    return "P3"


def selection_sort_key(candidate: dict[str, Any]) -> tuple[int, int, int, int, str]:
    severity = (candidate.get("suggested") or {}).get("severity") or "info_candidate"
    rank = SEVERITY_RANK.get(severity, 9)
    score = int(candidate.get("score") or 0)
    occurrences = int(candidate.get("occurrences") or 1)
    category = candidate.get("category_primary") or ""
    cat_rank = CATEGORY_PRIORITY.get(category, 99)
    text = candidate.get("rule_text") or ""
    return (rank, -score, -occurrences, cat_rank, text)


def build_record(idx: int, candidate: dict[str, Any]) -> dict[str, Any]:
    suggested = candidate.get("suggested") or {}
    severity = suggested.get("severity") or "info_candidate"
    score = int(candidate.get("score") or 0)
    targets = target_blocks_for(candidate)

    return {
        "batch_rank": idx,
        "candidate_id": candidate.get("id"),
        "review_priority": review_priority_for(severity, score),
        "validation_status": "pending_review",
        "review_result": None,
        "reviewer_notes": "",
        "engine_target_suggestion": targets,
        "requires_regression_tests": severity in {"blocking_candidate", "warning_candidate"} or score >= 9,
        "candidate": candidate,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Build top-N validation batch from extracted engine rule candidates")
    parser.add_argument(
        "--input",
        default="engine_rule_candidates.json",
        help="Path to engine_rule_candidates.json",
    )
    parser.add_argument(
        "--output",
        default="engine_rule_validation_batch_top50.json",
        help="Output validation batch path",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Number of records to select",
    )
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    source = json.loads(input_path.read_text(encoding="utf-8"))
    candidates = source.get("candidates") or []

    sorted_candidates = sorted(candidates, key=selection_sort_key)
    selected = sorted_candidates[: max(1, args.limit)]

    records = [build_record(i + 1, c) for i, c in enumerate(selected)]

    priority_counts: dict[str, int] = {}
    severity_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    for record in records:
        priority = record["review_priority"]
        priority_counts[priority] = priority_counts.get(priority, 0) + 1

        severity = (((record.get("candidate") or {}).get("suggested") or {}).get("severity")) or "info_candidate"
        severity_counts[severity] = severity_counts.get(severity, 0) + 1

        category = ((record.get("candidate") or {}).get("category_primary")) or "unknown"
        category_counts[category] = category_counts.get(category, 0) + 1

    payload = {
        "metadata": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_file": input_path.name,
            "selection_rule": "severity asc (blocking/warning first), then score desc, then occurrences desc",
            "selected_count": len(records),
            "priority_counts": priority_counts,
            "severity_counts": severity_counts,
            "category_counts": category_counts,
        },
        "records": records,
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(records)} validation records to {output_path}")


if __name__ == "__main__":
    main()
