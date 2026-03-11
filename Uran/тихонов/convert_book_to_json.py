#!/usr/bin/env python3
import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path


PART_RE = re.compile(r"^ЧАСТЬ\s*([А-ЯЁA-Z0-9IVXLCM]+(?:\s+[А-ЯЁA-Z0-9IVXLCM]+)*)$", re.IGNORECASE)
SECTION_RE = re.compile(r"^РАЗДЕЛ\s*([0-9IVXLCM]+)$", re.IGNORECASE)
CHAPTER_RE = re.compile(r"^ГЛАВА\s*([0-9IVXLCM]+)$", re.IGNORECASE)


def collapse_spaced_letters(text: str) -> str:
    return re.sub(
        r"\b(?:[А-ЯЁа-яё] ){2,}[А-ЯЁа-яё]\b",
        lambda m: m.group(0).replace(" ", ""),
        text,
    )


def normalize_line(line: str) -> str:
    cleaned = line.strip()
    cleaned = collapse_spaced_letters(cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned


def heading_level(norm_line: str) -> int | None:
    upper = norm_line.upper()
    if PART_RE.match(upper):
        return 1
    if SECTION_RE.match(upper):
        return 2
    if CHAPTER_RE.match(upper):
        return 3
    return None


def canonical_heading(norm_line: str, level: int) -> str:
    upper = norm_line.upper()
    if level == 1:
        m = PART_RE.match(upper)
        if m:
            return f"ЧАСТЬ {m.group(1)}".strip()
    if level == 2:
        m = SECTION_RE.match(upper)
        if m:
            return f"РАЗДЕЛ {m.group(1)}"
    if level == 3:
        m = CHAPTER_RE.match(upper)
        if m:
            return f"Глава {m.group(1)}"
    return norm_line


def chunks_from_text(text: str, max_chars: int = 1800, overlap_chars: int = 180) -> list[str]:
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    current = ""

    for para in paragraphs:
        candidate = f"{current}\n\n{para}".strip() if current else para
        if len(candidate) <= max_chars:
            current = candidate
            continue

        if current:
            chunks.append(current)

        if len(para) <= max_chars:
            current = para
            continue

        start = 0
        while start < len(para):
            part = para[start : start + max_chars]
            chunks.append(part.strip())
            if start + max_chars >= len(para):
                break
            start += max_chars - overlap_chars
        current = ""

    if current:
        chunks.append(current)

    return chunks


def build_json(text: str, source_file: Path) -> dict:
    lines = text.splitlines()
    headings: list[dict] = []

    for idx, raw in enumerate(lines, start=1):
        normalized = normalize_line(raw)
        if not normalized:
            continue
        level = heading_level(normalized)
        if level is None:
            continue
        headings.append(
            {
                "line": idx,
                "level": level,
                "title": canonical_heading(normalized, level),
            }
        )

    if not headings:
        raise RuntimeError("Не удалось найти структуру (ЧАСТЬ/РАЗДЕЛ/ГЛАВА) в тексте.")

    nodes: list[dict] = []
    stack: list[dict] = []

    def parent_for(level: int) -> str | None:
        for item in reversed(stack):
            if item["level"] < level:
                return item["id"]
        return None

    for i, h in enumerate(headings):
        start_line = h["line"]
        end_line = headings[i + 1]["line"] - 1 if i + 1 < len(headings) else len(lines)
        body_lines = lines[start_line - 1 : end_line]
        body_text = "\n".join(body_lines).strip()

        node_id = f"s{i + 1:04d}"
        node = {
            "id": node_id,
            "level": h["level"],
            "title": h["title"],
            "start_line": start_line,
            "end_line": end_line,
            "parent_id": parent_for(h["level"]),
            "char_count": len(body_text),
            "text": body_text,
        }
        nodes.append(node)

        stack = [s for s in stack if s["level"] < h["level"]]
        stack.append({"id": node_id, "level": h["level"]})

    chunks: list[dict] = []
    chunk_counter = 1
    for node in nodes:
        if node["level"] != 3:
            continue
        node_chunks = chunks_from_text(node["text"])
        for idx, chunk_text in enumerate(node_chunks, start=1):
            chunks.append(
                {
                    "id": f"c{chunk_counter:05d}",
                    "section_id": node["id"],
                    "section_title": node["title"],
                    "chunk_index": idx,
                    "char_count": len(chunk_text),
                    "text": chunk_text,
                }
            )
            chunk_counter += 1

    total_chars = len(text)
    total_lines = len(lines)
    return {
        "metadata": {
            "source_file": str(source_file.name),
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "language": "ru",
            "encoding": "utf-8",
            "total_lines": total_lines,
            "total_chars": total_chars,
            "sections_count": len(nodes),
            "chapter_chunks_count": len(chunks),
            "chunking": {
                "target": "chapters_only",
                "max_chars": 1800,
                "overlap_chars": 180,
            },
        },
        "sections": nodes,
        "chunks": chunks,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert extracted book text into structured JSON")
    parser.add_argument("--input", required=True, help="Path to extracted .txt file")
    parser.add_argument("--output", required=True, help="Path to output .json file")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    text = input_path.read_text(encoding="utf-8", errors="ignore")
    text = text.replace("\x00", "").replace("\f", "\n")
    text = re.sub(r"\n{3,}", "\n\n", text)
    # The source contains a trailing table of contents duplicating structure.
    # Keep only the main body if "СОДЕРЖАНИЕ" appears close to the end.
    toc_match = None
    for m in re.finditer(r"\n\s*СОДЕРЖАНИЕ\s*\n", text, flags=re.IGNORECASE):
        toc_match = m
    if toc_match and toc_match.start() > int(len(text) * 0.7):
        text = text[: toc_match.start()].rstrip() + "\n"

    payload = build_json(text, input_path)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
