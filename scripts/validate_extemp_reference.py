#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


REQUIRED_COLUMNS = ("NameLatNom", "NameLatGen", "Type")

BOOLEAN_COLUMNS = {
    "NeedsTrituration",
    "IsListA_Poison",
    "IsNarcotic",
    "List_A",
    "List_B",
    "Strain",
    "PressMarc",
    "BringToVolume",
    "IsHerbalMix",
    "ShakeDaily",
    "Filter",
    "Sterile",
    "IsOintmentFitocomp",
}

FLOAT_COLUMNS = {
    "VrdG",
    "VsdG",
    "GttsPerMl",
    "Density",
    "E_Factor",
    "KUO",
    "KV",
    "ointment_ratio_solute_to_solvent",
    "PedsVrdG",
    "PedsRdG",
    "VrdChild_0_1",
    "VrdChild_1_6",
    "VrdChild_7_14",
    "WaterTempC",
    "ShelfLifeHours",
    "MacerationDays",
    "BufferPH",
    "BufferMolarity",
}

INT_COLUMNS = {
    "HeatBathMin",
    "StandMin",
    "CoolMin",
}

KNOWN_TRUTHY = {"yes", "y", "true", "1", "так", "да", "+"}
KNOWN_FALSY = {"no", "n", "false", "0", "ні", "нет", "-"}


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    line: int | None = None


def parse_line_swift_like(line: str) -> List[str]:
    out: List[str] = []
    cur: List[str] = []
    in_quotes = False
    chars = list(line)
    i = 0
    while i < len(chars):
        ch = chars[i]
        if ch == '"':
            if in_quotes and i + 1 < len(chars) and chars[i + 1] == '"':
                cur.append('"')
                i += 2
                continue
            in_quotes = not in_quotes
            i += 1
            continue
        if ch == "," and not in_quotes:
            out.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out


def normalize_reference_type(raw: str) -> Tuple[str, bool]:
    trimmed = raw.strip()
    if not trimmed:
        return "", False

    lower = trimmed.lower()
    compact = "".join(ch for ch in lower if ch.isalnum())
    mapping = {
        "act": "act",
        "active": "act",
        "activeingredient": "act",
        "substance": "act",
        "substantia": "act",
        "medicinalsubstance": "act",
        "aux": "aux",
        "auxiliary": "aux",
        "excipient": "aux",
        "solv": "solvent",
        "solvent": "solvent",
        "diluent": "solvent",
        "vehicle": "solvent",
        "base": "base",
        "ointmentbase": "base",
        "oilbase": "base",
        "fattybase": "base",
        "hydrophobicbase": "base",
        "polymerbase": "base",
        "isotonicbase": "base",
        "buffersolution": "buffersolution",
        "buffer": "buffersolution",
        "tincture": "tincture",
        "extract": "extract",
        "syrup": "syrup",
        "juice": "juice",
        "suspension": "suspension",
        "emulsion": "emulsion",
        "herbalraw": "herbalraw",
        "herbalmix": "herbalmix",
        "ointmentphyto": "act",
        "topicalphytomodern": "act",
        "insolublepowder": "act",
        "liquidstandard": "standardsolution",
        "standardliquid": "standardsolution",
        "standardsolution": "standardsolution",
        "standardstocksolution": "standardsolution",
        "officinalsolution": "standardsolution",
        "viscousliquid": "viscous liquid",
        "liquid": "liquid",
        "жидкие": "liquid",
        "жидкая": "liquid",
        "жидкий": "liquid",
        "рідкі": "liquid",
        "рідка": "liquid",
        "рідкий": "liquid",
        "твердые": "act",
        "твердый": "act",
        "твердое": "act",
        "твердыи": "act",
        "тверда": "act",
        "твердий": "act",
        "тверде": "act",
        "alcoholic": "alcoholic",
    }
    if compact in mapping:
        return mapping[compact], False
    return lower, True


def normalize_name_key(raw: str) -> str:
    return " ".join(raw.strip().lower().split())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Uran/extemp_reference_200.csv for app-import readiness."
    )
    parser.add_argument(
        "--file",
        default="/Users/eugentamara/URAN/Uran/extemp_reference_200.csv",
        help="Path to CSV file.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors.",
    )
    parser.add_argument(
        "--show-limit",
        type=int,
        default=12,
        help="Max issue lines to print.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    csv_path = Path(args.file)
    if not csv_path.exists():
        print(f"ERROR: file not found: {csv_path}")
        return 2

    raw_text = csv_path.read_text(encoding="utf-8-sig")
    lines = raw_text.splitlines()
    if not lines:
        print("ERROR: CSV is empty")
        return 2

    header = parse_line_swift_like(lines[0])
    header_len = len(header)
    header_index: Dict[str, int] = {name: i for i, name in enumerate(header)}
    issues: List[Issue] = []

    for col in REQUIRED_COLUMNS:
        if col not in header_index:
            issues.append(Issue("ERROR", "missing_column", f"Missing required column '{col}'"))

    rows: List[Tuple[int, List[str]]] = []
    shape_overflow_blank = 0
    shape_underflow = 0
    shape_overflow_nonempty = 0

    for line_no, line in enumerate(lines[1:], start=2):
        trimmed = line.strip()
        if not trimmed:
            continue
        cols = parse_line_swift_like(trimmed)
        if len(cols) > header_len:
            extra = [cell.strip() for cell in cols[header_len:]]
            if any(extra):
                shape_overflow_nonempty += 1
                issues.append(
                    Issue(
                        "ERROR",
                        "row_overflow_nonempty",
                        f"Row has {len(cols)} columns; expected {header_len}. Non-empty overflow columns found.",
                        line_no,
                    )
                )
            else:
                shape_overflow_blank += 1
            cols = cols[:header_len]
        elif len(cols) < header_len:
            shape_underflow += 1
            issues.append(
                Issue(
                    "ERROR",
                    "row_underflow",
                    f"Row has {len(cols)} columns; expected {header_len}.",
                    line_no,
                )
            )
            cols = cols + [""] * (header_len - len(cols))
        rows.append((line_no, cols))

    name_to_rows: Dict[str, List[int]] = defaultdict(list)
    name_to_types: Dict[str, set[str]] = defaultdict(set)
    type_counter = Counter()

    def cell(row: List[str], col_name: str) -> str:
        idx = header_index.get(col_name)
        if idx is None or idx >= len(row):
            return ""
        return row[idx].strip()

    for line_no, row in rows:
        lat_nom = cell(row, "NameLatNom")
        lat_gen = cell(row, "NameLatGen")
        type_raw = cell(row, "Type")

        if not lat_nom:
            issues.append(Issue("ERROR", "empty_namelatnom", "NameLatNom is empty.", line_no))
        if not lat_gen:
            issues.append(Issue("ERROR", "empty_namelatgen", "NameLatGen is empty.", line_no))
        if not type_raw:
            issues.append(Issue("ERROR", "empty_type", "Type is empty.", line_no))

        type_norm, is_unknown_type = normalize_reference_type(type_raw)
        if type_raw:
            type_counter[type_norm or type_raw.lower()] += 1
        if is_unknown_type:
            issues.append(
                Issue(
                    "WARN",
                    "unknown_type",
                    f"Unknown Type '{type_raw}'. App will keep it as-is and logic may degrade.",
                    line_no,
                )
            )

        key = normalize_name_key(lat_nom)
        if key:
            name_to_rows[key].append(line_no)
            if type_norm:
                name_to_types[key].add(type_norm)

        for col in BOOLEAN_COLUMNS:
            value = cell(row, col)
            if not value:
                continue
            lowered = value.lower()
            if lowered not in KNOWN_TRUTHY and lowered not in KNOWN_FALSY:
                issues.append(
                    Issue(
                        "WARN",
                        "non_bool_value",
                        f"{col} has non-bool value '{value}'. App may treat it as false.",
                        line_no,
                    )
                )

        for col in FLOAT_COLUMNS:
            value = cell(row, col)
            if not value or value == "-":
                continue
            try:
                float(value.replace(",", "."))
            except ValueError:
                issues.append(
                    Issue(
                        "WARN",
                        "non_numeric_float",
                        f"{col} has non-numeric value '{value}'. App importer will drop it.",
                        line_no,
                    )
                )

        for col in INT_COLUMNS:
            value = cell(row, col)
            if not value or value == "-":
                continue
            try:
                int(value)
            except ValueError:
                try:
                    float(value.replace(",", "."))
                except ValueError:
                    issues.append(
                        Issue(
                            "WARN",
                            "non_numeric_int",
                            f"{col} has non-integer value '{value}'. App importer will drop it.",
                            line_no,
                        )
                    )

    for key, row_numbers in name_to_rows.items():
        if len(row_numbers) > 1:
            preview = ", ".join(str(n) for n in row_numbers[:6])
            issues.append(
                Issue(
                    "ERROR",
                    "duplicate_namelatnom",
                    f"Duplicate NameLatNom '{key}' at lines: {preview}",
                )
            )

    for key, types in name_to_types.items():
        if len(types) > 1:
            issues.append(
                Issue(
                    "ERROR",
                    "type_conflict",
                    f"Conflicting normalized Type for '{key}': {sorted(types)}",
                )
            )

    errors = [i for i in issues if i.severity == "ERROR"]
    warnings = [i for i in issues if i.severity == "WARN"]
    by_code = Counter((i.severity, i.code) for i in issues)

    print(f"File: {csv_path}")
    print(f"Header columns: {header_len}")
    print(f"Data rows (non-empty): {len(rows)}")
    print(f"Row shape: overflow_blank={shape_overflow_blank}, overflow_nonempty={shape_overflow_nonempty}, underflow={shape_underflow}")
    print(f"Types (normalized): {dict(type_counter)}")
    print(f"Issues: errors={len(errors)}, warnings={len(warnings)}")
    if by_code:
        print("Issue breakdown:")
        for (severity, code), count in sorted(by_code.items(), key=lambda item: (-item[1], item[0][0], item[0][1])):
            print(f"  - {severity} {code}: {count}")

    shown = 0
    for issue in issues:
        if shown >= args.show_limit:
            break
        prefix = f"{issue.severity}"
        if issue.line is not None:
            prefix += f" L{issue.line}"
        print(f"{prefix} [{issue.code}] {issue.message}")
        shown += 1

    if len(issues) > shown:
        print(f"... and {len(issues) - shown} more issues")

    failed = bool(errors) or (args.strict and bool(warnings))
    print(f"APP_IMPORT_READINESS: {'FAIL' if failed else 'PASS'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
