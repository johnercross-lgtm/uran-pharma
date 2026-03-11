import Foundation
import SwiftUI

enum SubstanceSegmentKind {
    case venena
    case heroica
    case lightSensitive
    case herbal
    case general

    var priority: Int {
        switch self {
        case .venena:
            return 5
        case .heroica:
            return 4
        case .lightSensitive:
            return 3
        case .herbal:
            return 2
        case .general:
            return 1
        }
    }

    var color: Color {
        switch self {
        case .venena:
            return .red
        case .heroica:
            return .blue
        case .lightSensitive:
            return .orange
        case .herbal:
            return .green
        case .general:
            return .gray
        }
    }
}

private struct SubstanceAliasPattern {
    let regex: NSRegularExpression
    let segment: SubstanceSegmentKind
    let aliasLength: Int
}

private struct SubstanceMatch {
    let range: NSRange
    let segment: SubstanceSegmentKind
    let aliasLength: Int
}

private struct SubstanceSegmentationCatalog {
    static let shared = SubstanceSegmentationCatalog()

    private let patterns: [SubstanceAliasPattern]

    private init() {
        patterns = Self.loadPatternsFromBundle()
    }

    func matches(in source: String) -> [SubstanceMatch] {
        guard !source.isEmpty else { return [] }
        let lineRange = NSRange(source.startIndex..<source.endIndex, in: source)

        var candidates: [SubstanceMatch] = []
        for pattern in patterns {
            let hits = pattern.regex.matches(in: source, options: [], range: lineRange)
            if hits.isEmpty { continue }
            for hit in hits where hit.range.location != NSNotFound && hit.range.length > 0 {
                candidates.append(
                    SubstanceMatch(
                        range: hit.range,
                        segment: pattern.segment,
                        aliasLength: pattern.aliasLength
                    )
                )
            }
        }

        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.segment.priority != rhs.segment.priority {
                return lhs.segment.priority > rhs.segment.priority
            }
            if lhs.aliasLength != rhs.aliasLength {
                return lhs.aliasLength > rhs.aliasLength
            }
            return lhs.range.location < rhs.range.location
        }

        var accepted: [SubstanceMatch] = []
        for candidate in sorted {
            let hasOverlap = accepted.contains { existing in
                let left = max(existing.range.location, candidate.range.location)
                let right = min(existing.range.location + existing.range.length, candidate.range.location + candidate.range.length)
                return left < right
            }
            if !hasOverlap {
                accepted.append(candidate)
            }
        }

        return accepted.sorted { $0.range.location < $1.range.location }
    }

    private static func loadPatternsFromBundle() -> [SubstanceAliasPattern] {
        guard let url = Bundle.main.url(forResource: "extemp_reference_200", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let parsed = parseCsvWithHeader(csv)
        guard !parsed.header.isEmpty else { return [] }

        let headerIndex = buildHeaderIndex(parsed.header)
        func idx(_ names: String...) -> Int? {
            for name in names {
                let key = normalizedHeaderKey(name)
                if let found = headerIndex[key] {
                    return found
                }
            }
            return nil
        }

        guard let latNomIndex = idx("NameLatNom", "name_lat_nom"),
              let latGenIndex = idx("NameLatGen", "name_lat_gen"),
              let ruIndex = idx("rus", "NameRu", "name_ru") else {
            return []
        }

        let listAIndex = idx("List_A", "list_a")
        let listBIndex = idx("List_B", "list_b")
        let poisonIndex = idx("IsListA_Poison", "islista_poison")
        let byNatureIndex = idx("ByNature", "by_nature")
        let naturalGroupIndex = idx("NaturalGroup", "natural_group")
        let isHerbalMixIndex = idx("IsHerbalMix", "is_herbal_mix")
        let herbalPartIndex = idx("HerbalPart", "herbal_part")
        let prepMethodIndex = idx("PrepMethod", "prep_method")
        let storageIndex = idx("Storage", "storage")
        let interactionIndex = idx("InteractionNotes", "interaction_notes")
        let notesSolventIndex = idx("NotesSolvent", "notes_solvent")
        let notesBaseIndex = idx("NotesBase", "notes_base")
        let notesHerbalIndex = idx("NotesHerbal", "notes_herbal")

        var aliasToSegment: [String: SubstanceSegmentKind] = [:]
        aliasToSegment.reserveCapacity(parsed.rows.count * 2)

        for row in parsed.rows {
            guard latNomIndex < row.count, latGenIndex < row.count, ruIndex < row.count else { continue }

            let latNom = cleaned(row[latNomIndex])
            let latGen = cleaned(row[latGenIndex])
            let ru = cleaned(row[ruIndex])
            guard !(latNom.isEmpty && latGen.isEmpty && ru.isEmpty) else { continue }

            let isListA = isTruthy(value(at: listAIndex, in: row)) || isTruthy(value(at: poisonIndex, in: row))
            let isListB = isTruthy(value(at: listBIndex, in: row))
            let byNature = normalize(value(at: byNatureIndex, in: row))
            let naturalGroup = normalize(value(at: naturalGroupIndex, in: row))
            let isHerbalMix = isTruthy(value(at: isHerbalMixIndex, in: row))
            let herbalPart = normalize(value(at: herbalPartIndex, in: row))
            let prepMethod = normalize(value(at: prepMethodIndex, in: row))

            let lightHay = normalize([
                value(at: storageIndex, in: row),
                value(at: interactionIndex, in: row),
                value(at: notesSolventIndex, in: row),
                value(at: notesBaseIndex, in: row),
                value(at: notesHerbalIndex, in: row),
                value(at: prepMethodIndex, in: row)
            ].joined(separator: " "))
            let isStableBromide = isStableBromideSalt(latNom: latNom, latGen: latGen, ru: ru)
            let isLightSensitive = !isStableBromide
                && !containsNegativeLightMarker(lightHay)
                && containsAny(
                    in: lightHay,
                    terms: [
                        "light",
                        "свет",
                        "світ",
                        "darkglass",
                        "оранж",
                        "orange",
                        "lightprotected",
                        "lightsensitive",
                        "light sensitive",
                        "захищеному від світла",
                        "защищенном от света"
                    ]
                )

            let isNatural = containsAny(in: byNature, terms: ["природ", "натурал", "растит", "herbal", "plant"])
                || !naturalGroup.isEmpty
                || isHerbalMix
                || !herbalPart.isEmpty
                || containsAny(in: prepMethod, terms: ["настой", "настоян", "інфуз", "infus", "відвар", "decoct"])

            let segment: SubstanceSegmentKind = {
                if isListA { return .venena }
                if isListB { return .heroica }
                if isLightSensitive { return .lightSensitive }
                if isNatural { return .herbal }
                return .general
            }()

            for rawAlias in [latNom, latGen, ru] {
                let alias = cleaned(rawAlias)
                guard alias.count >= 4 else { continue }
                if let existing = aliasToSegment[alias], existing.priority >= segment.priority {
                    continue
                }
                aliasToSegment[alias] = segment
            }
        }

        var built: [SubstanceAliasPattern] = []
        built.reserveCapacity(aliasToSegment.count)
        for (alias, segment) in aliasToSegment {
            guard let regex = makeAliasRegex(alias) else { continue }
            built.append(SubstanceAliasPattern(regex: regex, segment: segment, aliasLength: alias.count))
        }

        return built.sorted { lhs, rhs in
            if lhs.aliasLength != rhs.aliasLength {
                return lhs.aliasLength > rhs.aliasLength
            }
            return lhs.segment.priority > rhs.segment.priority
        }
    }

    private static func makeAliasRegex(_ alias: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
            .replacingOccurrences(of: "\\ ", with: "\\s+")
        let pattern = #"(?i)(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }

    private static func value(at index: Int?, in row: [String]) -> String {
        guard let index, index < row.count else { return "" }
        return row[index]
    }

    private static func isTruthy(_ raw: String) -> Bool {
        let value = cleaned(raw).lowercased()
        return value == "yes" || value == "true" || value == "1" || value == "да" || value == "так"
    }

    private static func containsAny(in source: String, terms: [String]) -> Bool {
        terms.contains { source.contains($0) }
    }

    private static func containsNegativeLightMarker(_ source: String) -> Bool {
        containsAny(
            in: source,
            terms: [
                "не світлочут",
                "не светочувств",
                "світлозахист не потріб",
                "защита от света не треб",
                "not light sensitive",
                "light protection not required",
                "protect from light not required"
            ]
        )
    }

    private static func isStableBromideSalt(latNom: String, latGen: String, ru: String) -> Bool {
        let hay = normalize([latNom, latGen, ru].joined(separator: " "))
        let hasBromide = containsAny(
            in: hay,
            terms: [
                "natrii bromid",
                "kalii bromid",
                "sodium bromide",
                "potassium bromide",
                "натрия бромид",
                "натрію бромід",
                "калия бромид",
                "калію бромід"
            ]
        )
        let hasHydrobromide = containsAny(in: hay, terms: ["hydrobromid", "гидробромид", "гідробромід"])
        return hasBromide && !hasHydrobromide
    }

    private static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildHeaderIndex(_ header: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        out.reserveCapacity(header.count)
        for (index, raw) in header.enumerated() {
            let key = normalizedHeaderKey(raw)
            if !key.isEmpty, out[key] == nil {
                out[key] = index
            }
        }
        return out
    }

    private static func normalizedHeaderKey(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = cleaned.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func parseCsvWithHeader(_ content: String) -> (header: [String], rows: [[String]]) {
        func parseLine(_ line: String) -> [String] {
            var columns: [String] = []
            var current = ""
            var inQuotes = false

            let chars = Array(line)
            var index = 0
            while index < chars.count {
                let ch = chars[index]
                if ch == "\"" {
                    if inQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                        current.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes.toggle()
                    index += 1
                    continue
                }
                if ch == "," && !inQuotes {
                    columns.append(current)
                    current = ""
                    index += 1
                    continue
                }
                current.append(ch)
                index += 1
            }
            columns.append(current)
            return columns
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        guard let first = lines.first else { return ([], []) }
        let header = parseLine(first)
        let rows: [[String]] = lines.dropFirst().compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            var cols = parseLine(trimmed)
            if cols.count > header.count {
                let extra = cols[header.count...]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if extra.contains(where: { !$0.isEmpty }) {
                    return nil
                }
                cols = Array(cols.prefix(header.count))
            } else if cols.count < header.count {
                cols.append(contentsOf: Array(repeating: "", count: header.count - cols.count))
            }
            return cols
        }
        return (header, rows)
    }
}

enum SubstanceTokenHighlighter {
    static func apply(to line: inout AttributedString, source: String) {
        let matches = SubstanceSegmentationCatalog.shared.matches(in: source)
        guard !matches.isEmpty else { return }

        for match in matches {
            guard let stringRange = Range(match.range, in: source),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: line),
                  let upper = AttributedString.Index(stringRange.upperBound, within: line) else { continue }
            line[lower..<upper].foregroundColor = match.segment.color
        }
    }
}
