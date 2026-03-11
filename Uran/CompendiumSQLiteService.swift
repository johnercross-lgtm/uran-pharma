import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CompendiumHit: Identifiable {
    let id: String
    let brandName: String?
    let inn: String?
    let atcCode: String?
}

struct CompendiumItemDetails: Identifiable {
    let id: String
    let brandName: String?
    let inn: String?
    let atcCode: String?
    let dosageForm: String?
    let composition: String?
    let pharmacologicalProperties: String?
    let indications: String?
    let dosageAdministration: String?
    let contraindications: String?
    let sideEffects: String?
    let interactions: String?
    let overdose: String?
    let storageConditions: String?
}

final class CompendiumSQLiteService {
    static let shared = CompendiumSQLiteService()
    private var db: OpaquePointer?
    private let dbFileName = "compendium_unified.sqlite"
    private let queue = DispatchQueue(label: "compendium.sqlite.queue")
    private enum QueryMode {
        case strict
        case relaxed
    }
    private init() {}

    func openIfNeeded() throws {
        if db != nil { return }
        let url = try ensureDatabaseCopiedToWritableLocation()
        try openDatabase(at: url)
    }

    func searchFTS(_ raw: String, limit: Int = 50) throws -> [CompendiumHit] {
        try queue.sync {
            try openIfNeeded()
            let fetchLimit = max(limit * 6, limit)
            let strictQuery = sanitizeFTSQuery(raw, mode: .strict)
            if strictQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }

            var out: [CompendiumHit] = []
            var seenIds = Set<String>()

            let strictHits = try executeFTSSearch(matchQuery: strictQuery, fetchLimit: fetchLimit)
            for hit in strictHits where seenIds.insert(hit.id).inserted {
                out.append(hit)
                if out.count >= limit { return out }
            }

            let relaxedQuery = sanitizeFTSQuery(raw, mode: .relaxed)
            if relaxedQuery.isEmpty || relaxedQuery == strictQuery {
                return out
            }

            let relaxedHits = try executeFTSSearch(matchQuery: relaxedQuery, fetchLimit: fetchLimit)
            for hit in relaxedHits where seenIds.insert(hit.id).inserted {
                out.append(hit)
                if out.count >= limit { break }
            }
            return out
        }
    }

    private func executeFTSSearch(matchQuery query: String, fetchLimit: Int) throws -> [CompendiumHit] {
        let sql = """
        SELECT c.id, c.brand_name, c.inn, c.atc_code
        FROM compendium_fts f
        JOIN compendium_item c ON c.id = f.id
        WHERE compendium_fts MATCH ?
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(fetchLimit))

        var out: [CompendiumHit] = []
        var seenIds = Set<String>()
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                let id = columnText(stmt, 0) ?? ""
                guard !id.isEmpty, seenIds.insert(id).inserted else { continue }
                out.append(.init(
                    id: id,
                    brandName: columnText(stmt, 1),
                    inn: columnText(stmt, 2),
                    atcCode: columnText(stmt, 3)
                ))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.prepare(message: lastErrorMessage())
            }
        }
        return out
    }

    func fetchItem(id: String) throws -> CompendiumItemDetails? {
        try queue.sync {
            try openIfNeeded()
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }

            let sql = """
            SELECT id, brand_name, inn, atc_code,
                   dosage_form, composition, pharmacological_properties, indications, dosage_administration,
                   contraindications, side_effects, interactions, overdose, storage_conditions
            FROM compendium_item
            WHERE id = ? LIMIT 1;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteError.prepare(message: lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)

            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return nil }
            if step != SQLITE_ROW { throw SQLiteError.prepare(message: lastErrorMessage()) }

            return CompendiumItemDetails(
                id: columnText(stmt, 0) ?? trimmed,
                brandName: columnText(stmt, 1),
                inn: columnText(stmt, 2),
                atcCode: columnText(stmt, 3),
                dosageForm: columnText(stmt, 4),
                composition: columnText(stmt, 5),
                pharmacologicalProperties: columnText(stmt, 6),
                indications: columnText(stmt, 7),
                dosageAdministration: columnText(stmt, 8),
                contraindications: columnText(stmt, 9),
                sideEffects: columnText(stmt, 10),
                interactions: columnText(stmt, 11),
                overdose: columnText(stmt, 12),
                storageConditions: columnText(stmt, 13)
            )
        }
    }

    // MARK: - Helpers

    private func ensureDatabaseCopiedToWritableLocation() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = appSupport.appendingPathComponent("URAN_DB", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let dest = folder.appendingPathComponent(dbFileName)
        if fm.fileExists(atPath: dest.path) { return dest }

        guard let src = Bundle.main.url(forResource: "compendium_unified", withExtension: "sqlite") else {
            throw SQLiteError.bundleMissing("Файл compendium_unified.sqlite не найден в Bundle. Проверь Copy Bundle Resources.")
        }
        try fm.copyItem(at: src, to: dest)
        return dest
    }

    private func openDatabase(at url: URL) throws {
        var conn: OpaquePointer?
        if sqlite3_open_v2(url.path, &conn, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            throw SQLiteError.open(message: lastErrorMessage(conn))
        }
        db = conn
    }

    private func sanitizeFTSQuery(_ s: String, mode: QueryMode = .strict) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Строим безопасный MATCH-запрос только из букв/цифр, чтобы не падать на синтаксисе FTS.
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)

        let stopWords: Set<String> = [
            "и", "или", "а", "но", "это", "эта", "этот", "для", "про", "по", "на", "в", "с",
            "мне", "моя", "мой", "мои", "у", "к", "от", "до", "как", "что", "где", "когда",
            "найди", "ищи", "покажи", "дай", "пожалуйста", "нужно", "надо",
            "доза", "дозы", "дозировка", "дозировке", "дозировку", "дозирован",
            "инструкция", "инструкцию", "инструкции", "показания", "показание",
            "противопоказания", "противопоказание", "побочки", "побочные", "побочка",
            "взаимодействие", "взаимодействия", "применение", "применять", "прием", "приема",
            "какая", "какой", "какие", "сколько"
        ]

        let rawTokens = normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
        var tokens: [String] = []
        for token in rawTokens where !tokens.contains(token) {
            tokens.append(token)
        }

        if tokens.isEmpty { return "" }
        let op = mode == .strict ? " AND " : " OR "
        return tokens.map { "\($0)*" }.joined(separator: op)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func lastErrorMessage(_ conn: OpaquePointer? = nil) -> String {
        let c = conn ?? db
        guard let c else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(c))
    }
}

enum SQLiteError: Error, LocalizedError {
    case bundleMissing(String)
    case open(message: String)
    case prepare(message: String)

    var errorDescription: String? {
        switch self {
        case .bundleMissing(let s): return s
        case .open(let m): return "SQLite open error: \(m)"
        case .prepare(let m): return "SQLite prepare error: \(m)"
        }
    }
}
