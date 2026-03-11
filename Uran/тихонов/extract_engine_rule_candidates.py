#!/usr/bin/env python3
import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DOC_ID = "tikhonov_aptechnaya_tekhnologia"


CATEGORY_PATTERNS: dict[str, list[tuple[re.Pattern[str], int, str]]] = {
    "dissolution": [
        (re.compile(r"\bраствор(?:ить|яют|яется|ение|имости|имый|им)\b", re.IGNORECASE), 3, "раствор"),
        (re.compile(r"\bдисперг(?:ировать|ируют|ация)\b", re.IGNORECASE), 2, "дисперг"),
    ],
    "heating": [
        (re.compile(r"\bнагрев(?:ать|ании|ания|ом)\b", re.IGNORECASE), 3, "нагрев"),
        (re.compile(r"\bкипяч(?:ение|ении|ивать|ивают)\b", re.IGNORECASE), 3, "кипяч"),
        (re.compile(r"\bводян(?:ая|ой)\s+бан", re.IGNORECASE), 3, "водяная баня"),
        (re.compile(r"\bохлад(?:ить|ить|ение|ении)\b", re.IGNORECASE), 2, "охлаждение"),
    ],
    "filtration": [
        (re.compile(r"\bфильтр(?:овать|уют|ация|ование|уют)\b", re.IGNORECASE), 3, "фильтрация"),
        (re.compile(r"\bпроцеж(?:ивать|ивание|ивают|енный)\b", re.IGNORECASE), 3, "процеживание"),
    ],
    "mixing_order": [
        (re.compile(r"\bперемеш(?:ать|ивание|ивают|ивать)\b", re.IGNORECASE), 2, "перемешивание"),
        (re.compile(r"\bдобав(?:ить|ляют|ление|лять)\b", re.IGNORECASE), 2, "добавление"),
        (re.compile(r"\bпоследовательност(?:ь|и)\b", re.IGNORECASE), 2, "последовательность"),
        (re.compile(r"\bсначала\b|\bзатем\b|\bпосле\b", re.IGNORECASE), 1, "порядок внесения"),
    ],
    "volume_adjustment": [
        (re.compile(r"\bдовест[ии]\b.*\bоб[ъь]?[её]м", re.IGNORECASE), 4, "довести до объема"),
        (re.compile(r"\bad\b", re.IGNORECASE), 2, "ad"),
        (re.compile(r"\bq\.?\s*s\.?\b", re.IGNORECASE), 2, "q.s."),
    ],
    "trituration": [
        (re.compile(r"\bизмельч(?:ение|ать|ают|енный)\b", re.IGNORECASE), 3, "измельчение"),
        (re.compile(r"\bрастир(?:ать|ание|ают|ка)\b", re.IGNORECASE), 3, "растирание"),
        (re.compile(r"\bтритурац(?:ия|ии)\b", re.IGNORECASE), 4, "тритурация"),
        (re.compile(r"\bступк(?:а|е|и)\b", re.IGNORECASE), 1, "ступка"),
    ],
    "sterility": [
        (re.compile(r"\bстерил(?:ьн|изац|ьность)\w*", re.IGNORECASE), 4, "стерильность"),
        (re.compile(r"\bасепт(?:ика|ически|ичн)\w*", re.IGNORECASE), 4, "асептика"),
    ],
    "safety_incompatibility": [
        (re.compile(r"\bнесовместим(?:ость|ы|о|а)?\b", re.IGNORECASE), 4, "несовместимость"),
        (re.compile(r"\bне\s+допуска(?:ется|ть)\b|\bзапрещ(?:ено|ается|ать)\b", re.IGNORECASE), 4, "запрет"),
        (re.compile(r"\bтоксич(?:ен|ность)\b|\bядовит\b", re.IGNORECASE), 3, "токсичность"),
        (re.compile(r"\bожог(?:и|ов)?\b", re.IGNORECASE), 2, "ожог"),
        (re.compile(r"\bогнеопас(?:ен|ность)\b|\bвоспламен\b", re.IGNORECASE), 3, "огнеопасность"),
        (re.compile(r"\bкоагул(?:яц|ирует)\w*", re.IGNORECASE), 2, "коагуляция"),
        (re.compile(r"\bосад(?:ок|ка|кообраз)\b", re.IGNORECASE), 2, "осадок"),
    ],
    "quality_storage": [
        (re.compile(r"\bконтрол(?:ь|я)\s+качеств", re.IGNORECASE), 3, "контроль качества"),
        (re.compile(r"\bхран(?:ить|ение|ят)\b", re.IGNORECASE), 2, "хранение"),
        (re.compile(r"\bсрок\s+годност", re.IGNORECASE), 2, "срок годности"),
        (re.compile(r"\bзащищ(?:ать|енном)\s+от\s+света", re.IGNORECASE), 2, "защита от света"),
        (re.compile(r"\bмаркиров(?:ка|ать)\b", re.IGNORECASE), 1, "маркировка"),
    ],
}


FORM_MARKERS: dict[str, list[re.Pattern[str]]] = {
    "solutions": [re.compile(r"\bраствор(?:ы|а|ов)?\b", re.IGNORECASE), re.compile(r"\bмикстур", re.IGNORECASE)],
    "drops": [re.compile(r"\bкапл(?:и|я|ях)?\b", re.IGNORECASE)],
    "powders": [re.compile(r"\bпорошк(?:и|ов|а)?\b", re.IGNORECASE), re.compile(r"\bприсыпк", re.IGNORECASE)],
    "ointments": [re.compile(r"\bмаз(?:ь|и|ей|ях)\b", re.IGNORECASE)],
    "suppositories": [re.compile(r"\bсуппозитор", re.IGNORECASE), re.compile(r"\bсвеч", re.IGNORECASE)],
    "infusions_decoctions": [re.compile(r"\bнасто(?:й|и)\b", re.IGNORECASE), re.compile(r"\bотвар(?:ы|а)?\b", re.IGNORECASE)],
}


SOLVENT_MARKERS: dict[str, list[re.Pattern[str]]] = {
    "water": [re.compile(r"\bвода\b|\baqua\b", re.IGNORECASE)],
    "ethanol": [re.compile(r"\bспирт\b|\bethanol\b|\baethanol\b", re.IGNORECASE)],
    "glycerin": [re.compile(r"\bглицерин\b|\bglycerin(?:um)?\b", re.IGNORECASE)],
    "oil": [re.compile(r"\bмасл(?:о|а|е)\b|\boleum\b", re.IGNORECASE)],
    "ether": [re.compile(r"\bэфир\b|\baether\b", re.IGNORECASE)],
    "chloroform": [re.compile(r"\bхлороформ\b|\bchloroform\b", re.IGNORECASE)],
}


ROUTE_MARKERS: dict[str, list[re.Pattern[str]]] = {
    "oral": [re.compile(r"\bвнутр(?:ь|енне)\b|\bper os\b", re.IGNORECASE)],
    "external": [re.compile(r"\bнаружн|\bзовнішн|\bдля\s+кожи|\bна\s+кожу\b", re.IGNORECASE)],
    "ophthalmic": [re.compile(r"\bглазн|\bочн|\bophth", re.IGNORECASE)],
}


SEVERITY_BLOCKING = [
    re.compile(r"\bне\s+допуска(?:ется|ть)\b|\bзапрещ(?:ено|ается|ать)\b", re.IGNORECASE),
    re.compile(r"\bнесовместим(?:ость|ы|о|а)?\b", re.IGNORECASE),
]
SEVERITY_WARNING = [
    re.compile(r"\bосторожно\b|\bриск\b|\bтоксич(?:ен|ность)\b", re.IGNORECASE),
    re.compile(r"\bогнеопас(?:ен|ность)\b|\bожог(?:и|ов)?\b", re.IGNORECASE),
]


NEGATIVE_HINTS = [
    re.compile(r"\bучебник\b|\bдисциплин\b|\bистори[яи]\b|\bсъезд\b", re.IGNORECASE),
    re.compile(r"\bтаблиц[аы]\b|\bсхем[аы]\b|\[pic\]", re.IGNORECASE),
]


LATIN_SUBSTANCE_RE = re.compile(r"\b([A-Z][a-z]{2,}(?:ii|um|as|is|ae|us|idum|atis)?)\b")


def normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def sentence_split(text: str) -> list[str]:
    cleaned = normalize_spaces(text.replace("\r", " ").replace("\n", " "))
    if not cleaned:
        return []
    rough = re.split(r"(?<=[\.\!\?\;\:])\s+", cleaned)
    return [normalize_spaces(part) for part in rough if normalize_spaces(part)]


def normalized_key(text: str) -> str:
    base = text.lower()
    base = re.sub(r"[^a-zа-яё0-9]+", " ", base, flags=re.IGNORECASE)
    return normalize_spaces(base)


def is_rejectable_fragment(sentence: str) -> bool:
    trimmed = sentence.strip()
    if not trimmed:
        return True
    if "[pic]" in trimmed.lower():
        return True
    if trimmed.count("|") >= 2:
        return True
    if re.match(r"^[0-9\s\+\-\=\%\.,:;]+$", trimmed):
        return True
    if trimmed.endswith((",", ";", ":")):
        return True
    # На границах overlap часто образуются обрывки без финального знака.
    if not re.search(r"[.!?]$", trimmed):
        if len(trimmed) < 160:
            return True
    if len(re.findall(r"[А-Яа-яA-Za-z]", trimmed)) < 18:
        return True
    return False


def classify_sentence(sentence: str) -> tuple[int, set[str], list[str]]:
    score = 0
    categories: set[str] = set()
    cues: list[str] = []

    for category, patterns in CATEGORY_PATTERNS.items():
        category_hit = False
        for pattern, weight, cue in patterns:
            if pattern.search(sentence):
                score += weight
                cues.append(cue)
                category_hit = True
        if category_hit:
            categories.add(category)

    if re.search(r"\b\d{2,3}\s*[-–]?\s*\d{0,3}\s*°?\s*c\b", sentence, flags=re.IGNORECASE):
        score += 2
        cues.append("температура")
    if re.search(r"\b\d+\s*(?:мин|час|ч)\b", sentence, flags=re.IGNORECASE):
        score += 1
        cues.append("время")
    if re.search(r"\bдолжн(?:о|ы|а)\b|\bследует\b|\bнеобходимо\b", sentence, flags=re.IGNORECASE):
        score += 2
        cues.append("нормативный модал")

    if re.search(r"\b(19|20)\d{2}\b", sentence) and score < 4:
        score -= 2

    for negative in NEGATIVE_HINTS:
        if negative.search(sentence):
            score -= 2

    if len(sentence) < 35:
        score -= 2
    if len(sentence) > 420:
        score -= 2

    return score, categories, sorted(set(cues))


def detect_forms(sentence: str) -> list[str]:
    out: list[str] = []
    for form, patterns in FORM_MARKERS.items():
        if any(pattern.search(sentence) for pattern in patterns):
            out.append(form)
    return out


def detect_solvents(sentence: str) -> list[str]:
    out: list[str] = []
    for solvent, patterns in SOLVENT_MARKERS.items():
        if any(pattern.search(sentence) for pattern in patterns):
            out.append(solvent)
    return out


def detect_routes(sentence: str) -> list[str]:
    out: list[str] = []
    for route, patterns in ROUTE_MARKERS.items():
        if any(pattern.search(sentence) for pattern in patterns):
            out.append(route)
    return out


def detect_substances(sentence: str) -> list[str]:
    matches = LATIN_SUBSTANCE_RE.findall(sentence)
    lowered = [m.lower() for m in matches]
    filtered = [m for m in lowered if m not in {"aqua", "rp", "da", "signa"}]
    unique: list[str] = []
    for name in filtered:
        if name not in unique:
            unique.append(name)
    return unique[:8]


def suggest_severity(sentence: str) -> str:
    if any(pattern.search(sentence) for pattern in SEVERITY_BLOCKING):
        return "blocking_candidate"
    if any(pattern.search(sentence) for pattern in SEVERITY_WARNING):
        return "warning_candidate"
    return "info_candidate"


def suggest_conflict_policy(severity: str) -> str:
    if severity == "blocking_candidate":
        return "prefer_existing_engine_rule_until_validated"
    return "append_as_hint_after_validation"


def reduce_to_primary_category(categories: set[str]) -> str:
    priority = [
        "safety_incompatibility",
        "sterility",
        "dissolution",
        "heating",
        "filtration",
        "mixing_order",
        "trituration",
        "volume_adjustment",
        "quality_storage",
    ]
    for name in priority:
        if name in categories:
            return name
    return "technology_other"


def source_ref(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "section_id": row.get("section_id"),
        "section_title": row.get("section_title"),
        "chunk_id": row.get("id"),
        "chunk_index": row.get("chunk_index"),
    }


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            obj = json.loads(line)
            if isinstance(obj, dict):
                rows.append(obj)
    return rows


def build_candidates(rows: list[dict[str, Any]], threshold: int) -> tuple[list[dict[str, Any]], dict[str, int], int]:
    by_key: dict[str, dict[str, Any]] = {}
    sentences_seen = 0

    for row in rows:
        text = row.get("text") or ""
        section_title = normalize_spaces(str(row.get("section_title") or ""))
        for sentence in sentence_split(text):
            sentences_seen += 1
            if is_rejectable_fragment(sentence):
                continue
            score, categories, cues = classify_sentence(sentence)
            if score < threshold or not categories:
                continue

            norm = normalized_key(sentence)
            if not norm or len(norm) < 20:
                continue

            severity = suggest_severity(sentence)
            forms = detect_forms(sentence)
            solvents = detect_solvents(sentence)
            routes = detect_routes(sentence)
            substances = detect_substances(sentence)
            primary = reduce_to_primary_category(categories)

            current = by_key.get(norm)
            if current is None:
                by_key[norm] = {
                    "rule_text": sentence,
                    "normalized_rule_text": norm,
                    "category_primary": primary,
                    "categories": sorted(categories),
                    "score": score,
                    "matched_cues": cues,
                    "status": "candidate",
                    "suggested": {
                        "severity": severity,
                        "applies_to": {
                            "forms": forms,
                            "solvents": solvents,
                            "routes": routes,
                            "substances": substances,
                            "section_hints": [section_title] if section_title else [],
                        },
                        "conflict_policy": suggest_conflict_policy(severity),
                    },
                    "sources": [source_ref(row)],
                    "occurrences": 1,
                }
                continue

            current["occurrences"] += 1
            current["score"] = max(current["score"], score)

            merged_categories = set(current["categories"]) | categories
            current["categories"] = sorted(merged_categories)
            current["category_primary"] = reduce_to_primary_category(merged_categories)
            current["matched_cues"] = sorted(set(current["matched_cues"]) | set(cues))

            applies_to = current["suggested"]["applies_to"]
            applies_to["forms"] = sorted(set(applies_to["forms"]) | set(forms))
            applies_to["solvents"] = sorted(set(applies_to["solvents"]) | set(solvents))
            applies_to["routes"] = sorted(set(applies_to["routes"]) | set(routes))
            applies_to["substances"] = sorted(set(applies_to["substances"]) | set(substances))
            if section_title and section_title not in applies_to["section_hints"]:
                applies_to["section_hints"].append(section_title)
                applies_to["section_hints"] = applies_to["section_hints"][:5]

            if severity == "blocking_candidate":
                current["suggested"]["severity"] = "blocking_candidate"
                current["suggested"]["conflict_policy"] = suggest_conflict_policy("blocking_candidate")
            elif severity == "warning_candidate" and current["suggested"]["severity"] == "info_candidate":
                current["suggested"]["severity"] = "warning_candidate"
                current["suggested"]["conflict_policy"] = suggest_conflict_policy("warning_candidate")

            ref = source_ref(row)
            if ref not in current["sources"] and len(current["sources"]) < 6:
                current["sources"].append(ref)

    candidates = sorted(
        by_key.values(),
        key=lambda item: (-int(item["score"]), item["category_primary"], item["rule_text"]),
    )

    for i, item in enumerate(candidates, start=1):
        item["id"] = f"cand_{i:05d}"

    category_counter = Counter(item["category_primary"] for item in candidates)
    return candidates, dict(category_counter), sentences_seen


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract candidate RxEngine rules from Tikhonov chunks")
    parser.add_argument(
        "--input",
        default="Tikhonov_Aptechnaya_tekhnologia_chunks.jsonl",
        help="Path to input JSONL chunks",
    )
    parser.add_argument(
        "--output",
        default="engine_rule_candidates.json",
        help="Path to output JSON file",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=5,
        help="Minimum score for candidate extraction",
    )
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    rows = load_jsonl(input_path)
    candidates, category_counts, sentences_seen = build_candidates(rows, threshold=args.threshold)

    severity_counts = Counter(c["suggested"]["severity"] for c in candidates)

    payload = {
        "metadata": {
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_file": input_path.name,
            "doc_id": DOC_ID,
            "threshold_score": args.threshold,
            "total_chunks_read": len(rows),
            "total_sentences_seen": sentences_seen,
            "unique_candidates": len(candidates),
            "category_counts": category_counts,
            "severity_counts": dict(severity_counts),
        },
        "candidates": candidates,
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(candidates)} candidates to {output_path}")


if __name__ == "__main__":
    main()
