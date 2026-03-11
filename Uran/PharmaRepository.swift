import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

final class PharmaRepository {
    private let queue = DispatchQueue(label: "pharma.sqlite.queue")
    private let sqlite: SQLiteService
    private let dbPath: String
    private var index: [(result: DrugSearchResult, searchText: String)]?
    private var compendiumIndex: CompendiumIndex?

    private let compendiumImportVersion: String = "компендиум1_enriched_units_fixed_v11_kopacyl_fix"

#if canImport(FirebaseFirestore)
    private let firestore = Firestore.firestore()
#endif

    private enum DatabaseSchema {
        case newDrugs
        case legacy
    }

    func loadParsedDosageCache(uaVariantId: String) async throws -> String? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            queue.async {
                do {
                    if let row = try self.sqlite.querySingleRow(
                        sql: """
                        SELECT parsed_json
                        FROM parsed_dosage_cache
                        WHERE ua_variant_id = ?
                        LIMIT 1
                        """,
                        binds: [.text(uaVariantId)]
                    ) {
                        let s = (row["parsed_json"] ?? nil) ?? ""
                        continuation.resume(returning: s.isEmpty ? nil : s)
                        return
                    }
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveParsedDosageCache(uaVariantId: String, parsedJson: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let now = Int64(Date().timeIntervalSince1970)
                    try self.sqlite.execute(
                        sql: """
                        INSERT INTO parsed_dosage_cache (ua_variant_id, parsed_json, updated_at)
                        VALUES (?, ?, ?)
                        ON CONFLICT(ua_variant_id) DO UPDATE SET
                            parsed_json = excluded.parsed_json,
                            updated_at = excluded.updated_at;
                        """,
                        binds: [.text(uaVariantId), .text(parsedJson), .int(now)]
                    )
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    enum RegistryScope: String, CaseIterable, Hashable {
        case all
        case ua
        case ru

        var dbValue: String {
            switch self {
            case .all: return ""
            case .ua: return "UA"
            case .ru: return "RU"
            }
        }
    }

    private var schema: DatabaseSchema?

    init() throws {
        let preferred = Bundle.main.url(forResource: "compendium_unified", withExtension: "sqlite")
            ?? Bundle.main.url(forResource: "compendium_unified", withExtension: "sqlite")
        guard let url = preferred else {
            throw SQLiteServiceError.openDatabaseFailed("compendium_unified.sqlite (или pharma_base 3.sqlite) не найден в app bundle. Проверь Target Membership / Copy Bundle Resources")
        }

        let targetFileName: String = "compendium_unified.sqlite"

        let fm = FileManager.default
        let supportDir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)

        let targetUrl = supportDir.appendingPathComponent(targetFileName)
        let walPath = targetUrl.path + "-wal"
        let shmPath = targetUrl.path + "-shm"

        // Remove legacy bases (if exist) to avoid accidentally reading the old file.
        let legacyTargetUrl = supportDir.appendingPathComponent("pharma_base.sqlite")
        let legacyWalPath = legacyTargetUrl.path + "-wal"
        let legacyShmPath = legacyTargetUrl.path + "-shm"
        if fm.fileExists(atPath: legacyTargetUrl.path) {
            try? fm.removeItem(at: legacyTargetUrl)
        }
        if fm.fileExists(atPath: legacyWalPath) {
            try? fm.removeItem(atPath: legacyWalPath)
        }
        if fm.fileExists(atPath: legacyShmPath) {
            try? fm.removeItem(atPath: legacyShmPath)
        }

        let legacyTargetUrl2 = supportDir.appendingPathComponent("pharma_base2.sqlite")
        let legacyWalPath2 = legacyTargetUrl2.path + "-wal"
        let legacyShmPath2 = legacyTargetUrl2.path + "-shm"
        if fm.fileExists(atPath: legacyTargetUrl2.path) {
            try? fm.removeItem(at: legacyTargetUrl2)
        }
        if fm.fileExists(atPath: legacyWalPath2) {
            try? fm.removeItem(atPath: legacyWalPath2)
        }
        if fm.fileExists(atPath: legacyShmPath2) {
            try? fm.removeItem(atPath: legacyShmPath2)
        }

        let targetExists = fm.fileExists(atPath: targetUrl.path)
        let bundleAttrs = try? fm.attributesOfItem(atPath: url.path)
        let targetAttrs = try? fm.attributesOfItem(atPath: targetUrl.path)

        let bundleSize = bundleAttrs?[.size] as? NSNumber
        let targetSize = targetAttrs?[.size] as? NSNumber
        let bundleMTime = bundleAttrs?[.modificationDate] as? Date
        let targetMTime = targetAttrs?[.modificationDate] as? Date

        let needsRefresh: Bool
        if !targetExists {
            needsRefresh = true
        } else if bundleSize != nil, targetSize != nil, bundleSize != targetSize {
            needsRefresh = true
        } else if let bundleMTime, let targetMTime, bundleMTime > targetMTime {
            needsRefresh = true
        } else {
            needsRefresh = false
        }

        var preservedAnnotations: [[String: String?]] = []
        if needsRefresh, targetExists {
            if let oldSqlite = try? SQLiteService(readOnlyDatabaseAtPath: targetUrl.path) {
                if let rows = try? oldSqlite.queryRows(
                    sql: """
                    SELECT ua_variant_id, dose_text, quantity_n, form_raw, signa_text, updated_at
                    FROM user_recipe_annotations
                    """,
                    binds: []
                ) {
                    preservedAnnotations = rows
                }
            }
        }

        if needsRefresh {
            if targetExists {
                try? fm.removeItem(at: targetUrl)
            }
            if fm.fileExists(atPath: walPath) {
                try? fm.removeItem(atPath: walPath)
            }
            if fm.fileExists(atPath: shmPath) {
                try? fm.removeItem(atPath: shmPath)
            }

            try fm.copyItem(at: url, to: targetUrl)
        }

        if fm.fileExists(atPath: walPath) {
            try? fm.removeItem(atPath: walPath)
        }
        if fm.fileExists(atPath: shmPath) {
            try? fm.removeItem(atPath: shmPath)
        }

        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: targetUrl.path)

        self.dbPath = targetUrl.path
        self.sqlite = try SQLiteService(readOnlyDatabaseAtPath: self.dbPath)

        try self.sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS user_recipe_annotations (
                ua_variant_id TEXT PRIMARY KEY,
                dose_text TEXT,
                quantity_n TEXT,
                form_raw TEXT,
                signa_text TEXT,
                volume_text TEXT,
                updated_at INTEGER
            );
            """,
            binds: []
        )

        // Backward compatible migration for existing installs.
        // If column already exists, SQLite will throw and we can ignore.
        try? self.sqlite.execute(
            sql: """
            ALTER TABLE user_recipe_annotations ADD COLUMN volume_text TEXT;
            """,
            binds: []
        )

        try self.sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS parsed_dosage_cache (
                ua_variant_id TEXT PRIMARY KEY,
                parsed_json TEXT NOT NULL,
                updated_at INTEGER
            );
            """,
            binds: []
        )

        try self.sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS note_folders (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                sort_order INTEGER,
                updated_at INTEGER,
                updated_by_uid TEXT
            );
            """,
            binds: []
        )

        try self.sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY,
                folder_id TEXT NOT NULL,
                title TEXT,
                content TEXT,
                updated_at INTEGER,
                updated_by_uid TEXT,
                updated_by_name TEXT
            );
            """,
            binds: []
        )

        // Backward compatible migration for existing installs.
        // If column already exists, SQLite will throw and we can ignore.
        try? self.sqlite.execute(
            sql: """
            ALTER TABLE notes ADD COLUMN updated_by_name TEXT;
            """,
            binds: []
        )

        try self.sqlite.execute(
            sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                note_id UNINDEXED,
                title,
                content,
                tokenize = 'unicode61'
            );
            """,
            binds: []
        )

        if !preservedAnnotations.isEmpty {
            for row in preservedAnnotations {
                let uaVariantId = (row["ua_variant_id"] ?? nil) ?? ""
                if uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                let doseText = (row["dose_text"] ?? nil)
                let quantityN = (row["quantity_n"] ?? nil)
                let formRaw = (row["form_raw"] ?? nil)
                let signaText = (row["signa_text"] ?? nil)
                let updatedAt = Int64((row["updated_at"] ?? nil) ?? "") ?? Int64(Date().timeIntervalSince1970)

                try self.sqlite.execute(
                    sql: """
                    INSERT INTO user_recipe_annotations (ua_variant_id, dose_text, quantity_n, form_raw, signa_text, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(ua_variant_id) DO UPDATE SET
                        dose_text = COALESCE(excluded.dose_text, user_recipe_annotations.dose_text),
                        quantity_n = COALESCE(excluded.quantity_n, user_recipe_annotations.quantity_n),
                        form_raw = COALESCE(excluded.form_raw, user_recipe_annotations.form_raw),
                        signa_text = COALESCE(excluded.signa_text, user_recipe_annotations.signa_text),
                        updated_at = excluded.updated_at;
                    """,
                    binds: [
                        .text(uaVariantId),
                        doseText != nil ? .text(doseText!) : .null,
                        quantityN != nil ? .text(quantityN!) : .null,
                        formRaw != nil ? .text(formRaw!) : .null,
                        signaText != nil ? .text(signaText!) : .null,
                        .int(updatedAt)
                    ]
                )
            }
        }

        do {
            try ensureCompendiumImportedIntoDrugsIfNeeded()
        } catch {
        }

        print("PharmaRepository DB:", self.dbPath)
    }

    private func queueSync<T>(_ work: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        queue.sync {
            result = Result { try work() }
        }
        return try result!.get()
    }

    func listNoteFolders() throws -> [NoteFolder] {
        try queueSync {
            let rows = try self.sqlite.queryRows(
                sql: """
                SELECT id, title, COALESCE(sort_order, 0) AS sort_order, COALESCE(updated_at, 0) AS updated_at, updated_by_uid
                FROM note_folders
                ORDER BY sort_order ASC, title COLLATE NOCASE ASC;
                """,
                binds: []
            )
            return rows.map { row in
                NoteFolder(
                    id: (row["id"] ?? nil) ?? "",
                    title: (row["title"] ?? nil) ?? "",
                    sortOrder: Int((row["sort_order"] ?? nil) ?? "0") ?? 0,
                    updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                    updatedByUid: (row["updated_by_uid"] ?? nil)
                )
            }.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    func loadNoteFolder(folderId: String) throws -> NoteFolder {
        try queueSync {
            guard let row = try self.sqlite.querySingleRow(
                sql: """
                SELECT id, title, COALESCE(sort_order, 0) AS sort_order, COALESCE(updated_at, 0) AS updated_at, updated_by_uid
                FROM note_folders
                WHERE id = ?
                LIMIT 1;
                """,
                binds: [.text(folderId)]
            ) else {
                throw SQLiteServiceError.stepFailed("folder not found")
            }
            return NoteFolder(
                id: (row["id"] ?? nil) ?? "",
                title: (row["title"] ?? nil) ?? "",
                sortOrder: Int((row["sort_order"] ?? nil) ?? "0") ?? 0,
                updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                updatedByUid: (row["updated_by_uid"] ?? nil)
            )
        }
    }

    @discardableResult
    func upsertNoteFolder(
        id: String?,
        title: String,
        sortOrder: Int?,
        updatedByUid: String?
    ) throws -> String {
        try queueSync {
            let folderId: String
            if let id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                folderId = id
            } else {
                folderId = UUID().uuidString
            }
            let now = Int64(Date().timeIntervalSince1970)
            try self.sqlite.execute(
                sql: """
                INSERT INTO note_folders (id, title, sort_order, updated_at, updated_by_uid)
                VALUES (?, ?, COALESCE(?, 0), ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    sort_order = COALESCE(excluded.sort_order, note_folders.sort_order),
                    updated_at = excluded.updated_at,
                    updated_by_uid = excluded.updated_by_uid;
                """,
                binds: [
                    .text(folderId),
                    .text(title),
                    sortOrder != nil ? .int(Int64(sortOrder!)) : .null,
                    .int(now),
                    updatedByUid != nil ? .text(updatedByUid!) : .null
                ]
            )
            return folderId
        }
    }

    func deleteNoteFolder(folderId: String) throws {
        try queueSync {
            try self.sqlite.execute(
                sql: """
                DELETE FROM notes_fts
                WHERE note_id IN (SELECT id FROM notes WHERE folder_id = ?);
                """,
                binds: [.text(folderId)]
            )
            try self.sqlite.execute(
                sql: """
                DELETE FROM notes WHERE folder_id = ?;
                """,
                binds: [.text(folderId)]
            )
            try self.sqlite.execute(
                sql: """
                DELETE FROM note_folders WHERE id = ?;
                """,
                binds: [.text(folderId)]
            )
        }
    }

    func listNotes(folderId: String, query: String?) throws -> [NoteItem] {
        try queueSync {
            let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                let rows = try self.sqlite.queryRows(
                    sql: """
                    SELECT id, folder_id, COALESCE(title, '') AS title, COALESCE(content, '') AS content,
                           COALESCE(updated_at, 0) AS updated_at, updated_by_uid, updated_by_name
                    FROM notes
                    WHERE folder_id = ?
                    ORDER BY updated_at DESC;
                    """,
                    binds: [.text(folderId)]
                )
                return rows.map { row in
                    NoteItem(
                        id: (row["id"] ?? nil) ?? "",
                        folderId: (row["folder_id"] ?? nil) ?? "",
                        title: (row["title"] ?? nil) ?? "",
                        content: (row["content"] ?? nil) ?? "",
                        updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                        updatedByUid: (row["updated_by_uid"] ?? nil),
                        updatedByName: (row["updated_by_name"] ?? nil)
                    )
                }.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

            let ftsQuery = trimmedQuery
                .replacingOccurrences(of: "\"", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0) + "*" }
                .joined(separator: " ")

            let rows = try self.sqlite.queryRows(
                sql: """
                SELECT n.id, n.folder_id, COALESCE(n.title, '') AS title, COALESCE(n.content, '') AS content,
                       COALESCE(n.updated_at, 0) AS updated_at, n.updated_by_uid, n.updated_by_name
                FROM notes n
                JOIN notes_fts f ON f.note_id = n.id
                WHERE n.folder_id = ? AND notes_fts MATCH ?
                ORDER BY n.updated_at DESC
                LIMIT 200;
                """,
                binds: [.text(folderId), .text(ftsQuery)]
            )
            return rows.map { row in
                NoteItem(
                    id: (row["id"] ?? nil) ?? "",
                    folderId: (row["folder_id"] ?? nil) ?? "",
                    title: (row["title"] ?? nil) ?? "",
                    content: (row["content"] ?? nil) ?? "",
                    updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                    updatedByUid: (row["updated_by_uid"] ?? nil),
                    updatedByName: (row["updated_by_name"] ?? nil)
                )
            }.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    func listNoteFeed(query: String?) throws -> [NoteFeedItem] {
        try queueSync {
            let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                let rows = try self.sqlite.queryRows(
                    sql: """
                    SELECT n.id, n.folder_id, COALESCE(n.title, '') AS title, COALESCE(n.content, '') AS content,
                           COALESCE(n.updated_at, 0) AS updated_at, n.updated_by_uid, n.updated_by_name,
                           COALESCE(f.title, '') AS folder_title
                    FROM notes n
                    LEFT JOIN note_folders f ON f.id = n.folder_id
                    ORDER BY n.updated_at DESC
                    LIMIT 500;
                    """,
                    binds: []
                )
                return rows.map { row in
                    let note = NoteItem(
                        id: (row["id"] ?? nil) ?? "",
                        folderId: (row["folder_id"] ?? nil) ?? "",
                        title: (row["title"] ?? nil) ?? "",
                        content: (row["content"] ?? nil) ?? "",
                        updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                        updatedByUid: (row["updated_by_uid"] ?? nil),
                        updatedByName: (row["updated_by_name"] ?? nil)
                    )
                    return NoteFeedItem(
                        note: note,
                        folderTitle: (row["folder_title"] ?? nil) ?? ""
                    )
                }.filter { !$0.note.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

            let ftsQuery = trimmedQuery
                .replacingOccurrences(of: "\"", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0) + "*" }
                .joined(separator: " ")

            let rows = try self.sqlite.queryRows(
                sql: """
                SELECT n.id, n.folder_id, COALESCE(n.title, '') AS title, COALESCE(n.content, '') AS content,
                       COALESCE(n.updated_at, 0) AS updated_at, n.updated_by_uid, n.updated_by_name,
                       COALESCE(f.title, '') AS folder_title
                FROM notes n
                JOIN notes_fts t ON t.note_id = n.id
                LEFT JOIN note_folders f ON f.id = n.folder_id
                WHERE notes_fts MATCH ?
                ORDER BY n.updated_at DESC
                LIMIT 500;
                """,
                binds: [.text(ftsQuery)]
            )

            return rows.map { row in
                let note = NoteItem(
                    id: (row["id"] ?? nil) ?? "",
                    folderId: (row["folder_id"] ?? nil) ?? "",
                    title: (row["title"] ?? nil) ?? "",
                    content: (row["content"] ?? nil) ?? "",
                    updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                    updatedByUid: (row["updated_by_uid"] ?? nil),
                    updatedByName: (row["updated_by_name"] ?? nil)
                )
                return NoteFeedItem(
                    note: note,
                    folderTitle: (row["folder_title"] ?? nil) ?? ""
                )
            }.filter { !$0.note.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    func loadNote(noteId: String) throws -> NoteItem {
        try queueSync {
            guard let row = try self.sqlite.querySingleRow(
                sql: """
                SELECT id, folder_id, COALESCE(title, '') AS title, COALESCE(content, '') AS content,
                       COALESCE(updated_at, 0) AS updated_at, updated_by_uid, updated_by_name
                FROM notes
                WHERE id = ?
                LIMIT 1;
                """,
                binds: [.text(noteId)]
            ) else {
                throw SQLiteServiceError.stepFailed("note not found")
            }
            return NoteItem(
                id: (row["id"] ?? nil) ?? "",
                folderId: (row["folder_id"] ?? nil) ?? "",
                title: (row["title"] ?? nil) ?? "",
                content: (row["content"] ?? nil) ?? "",
                updatedAt: Int64((row["updated_at"] ?? nil) ?? "0") ?? 0,
                updatedByUid: (row["updated_by_uid"] ?? nil),
                updatedByName: (row["updated_by_name"] ?? nil)
            )
        }
    }

    @discardableResult
    func upsertNote(
        id: String?,
        folderId: String,
        title: String,
        content: String,
        updatedByUid: String?,
        updatedByName: String? = nil
    ) throws -> String {
        try queueSync {
            let noteId = (id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? id! : UUID().uuidString
            let now = Int64(Date().timeIntervalSince1970)
            try self.sqlite.execute(
                sql: """
                INSERT INTO notes (id, folder_id, title, content, updated_at, updated_by_uid, updated_by_name)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    folder_id = excluded.folder_id,
                    title = excluded.title,
                    content = excluded.content,
                    updated_at = excluded.updated_at,
                    updated_by_uid = excluded.updated_by_uid,
                    updated_by_name = COALESCE(excluded.updated_by_name, notes.updated_by_name);
                """,
                binds: [
                    .text(noteId),
                    .text(folderId),
                    .text(title),
                    .text(content),
                    .int(now),
                    updatedByUid != nil ? .text(updatedByUid!) : .null,
                    updatedByName != nil ? .text(updatedByName!) : .null
                ]
            )

            try self.sqlite.execute(
                sql: """
                DELETE FROM notes_fts WHERE note_id = ?;
                """,
                binds: [.text(noteId)]
            )

            try self.sqlite.execute(
                sql: """
                INSERT INTO notes_fts (note_id, title, content)
                VALUES (?, ?, ?)
                """,
                binds: [
                    .text(noteId),
                    .text(title),
                    .text(content)
                ]
            )
            return noteId
        }
    }

    func deleteNote(noteId: String) throws {
        try queueSync {
            try self.sqlite.execute(
                sql: """
                DELETE FROM notes_fts WHERE note_id = ?;
                """,
                binds: [.text(noteId)]
            )
            try self.sqlite.execute(
                sql: """
                DELETE FROM notes WHERE id = ?;
                """,
                binds: [.text(noteId)]
            )
        }
    }

    private func loadLocalNoteUpdatedAt(noteId: String) throws -> Int64 {
        try queueSync {
            let row = try self.sqlite.querySingleRow(
                sql: """
                SELECT COALESCE(updated_at, 0) AS updated_at
                FROM notes
                WHERE id = ?
                LIMIT 1;
                """,
                binds: [.text(noteId)]
            )
            return Int64((row?["updated_at"] ?? nil) ?? "0") ?? 0
        }
    }

    private func loadLocalFolderUpdatedAt(folderId: String) throws -> Int64 {
        try queueSync {
            let row = try self.sqlite.querySingleRow(
                sql: """
                SELECT COALESCE(updated_at, 0) AS updated_at
                FROM note_folders
                WHERE id = ?
                LIMIT 1;
                """,
                binds: [.text(folderId)]
            )
            return Int64((row?["updated_at"] ?? nil) ?? "0") ?? 0
        }
    }

    @discardableResult
    func migrateLegacyMyNotesIfNeeded(
        legacyText: String,
        updatedByUid: String
    ) -> Bool {
        let trimmed = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let key = "notes_migrated_from_profile_v1"
        if UserDefaults.standard.bool(forKey: key) { return false }

        do {
            let folderId = try upsertNoteFolder(id: nil, title: "Конспект", sortOrder: 0, updatedByUid: updatedByUid)
            _ = try upsertNote(
                id: nil,
                folderId: folderId,
                title: "Мой конспект",
                content: trimmed,
                updatedByUid: updatedByUid
            )
            UserDefaults.standard.set(true, forKey: key)
            return true
        } catch {
            print("[PharmaRepository] migrateLegacyMyNotesIfNeeded failed: \(error)")
            return false
        }
    }

#if canImport(FirebaseFirestore)
    private func noteFoldersCollection() -> CollectionReference {
        firestore.collection("note_folders")
    }

    private func notesCollection() -> CollectionReference {
        firestore.collection("notes")
    }

    private func noteDeletesCollection() -> CollectionReference {
        firestore.collection("note_deletes")
    }

    func upsertNoteFolderToCloud(folderId: String, title: String, sortOrder: Int, updatedAt: Int64, updatedByUid: String) async {
        let payload: [String: Any] = [
            "id": folderId,
            "title": title,
            "sortOrder": sortOrder,
            "updatedAt": updatedAt,
            "updatedByUid": updatedByUid
        ]

        do {
            try await noteFoldersCollection().document(folderId).setData(payload, merge: true)
        } catch {
            print("[PharmaRepository] upsertNoteFolderToCloud failed: \(error)")
        }
    }

    func upsertNoteToCloud(
        noteId: String,
        folderId: String,
        title: String,
        content: String,
        updatedAt: Int64,
        updatedByUid: String,
        updatedByName: String? = nil,
        createdByUid: String? = nil
    ) async {
        var payload: [String: Any] = [
            "id": noteId,
            "folderId": folderId,
            "title": title,
            "content": content,
            "updatedAt": updatedAt,
            "updatedByUid": updatedByUid
        ]

        let name = (updatedByName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            payload["updatedByName"] = name
        }

        let c = (createdByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty {
            payload["createdByUid"] = c
        }

        do {
            try await notesCollection().document(noteId).setData(payload, merge: true)
        } catch {
            print("[PharmaRepository] upsertNoteToCloud failed: \(error)")
        }
    }

    func deleteNoteFromCloud(noteId: String, createdByUid: String? = nil) async {
        do {
            let deletedAt = Int64(Date().timeIntervalSince1970)
            var payload: [String: Any] = [
                "id": noteId,
                "deletedAt": deletedAt
            ]

            let c = (createdByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty {
                payload["createdByUid"] = c
            }

            try await noteDeletesCollection().document(noteId).setData(payload, merge: true)
            try await notesCollection().document(noteId).delete()
        } catch {
            print("[PharmaRepository] deleteNoteFromCloud failed: \(error)")
        }
    }

    func syncNotesFromCloud() async {
        do {
            let folderSnap = try await noteFoldersCollection().getDocuments()
            for doc in folderSnap.documents {
                let data = doc.data()
                let folderId = (data["id"] as? String) ?? doc.documentID
                let title = (data["title"] as? String) ?? ""
                let sortOrder = (data["sortOrder"] as? Int) ?? 0
                let updatedAt = (data["updatedAt"] as? Int64) ?? Int64((data["updatedAt"] as? Int) ?? 0)
                let updatedByUid = (data["updatedByUid"] as? String) ?? ""

                let localUpdated = (try? loadLocalFolderUpdatedAt(folderId: folderId)) ?? 0
                if updatedAt <= localUpdated { continue }
                _ = try? upsertNoteFolder(id: folderId, title: title, sortOrder: sortOrder, updatedByUid: updatedByUid)
            }

            let notesSnap = try await notesCollection().getDocuments()
            for doc in notesSnap.documents {
                let data = doc.data()
                let noteId = (data["id"] as? String) ?? doc.documentID
                let folderId = (data["folderId"] as? String) ?? ""
                let title = (data["title"] as? String) ?? ""
                let content = (data["content"] as? String) ?? ""
                let updatedAt = (data["updatedAt"] as? Int64) ?? Int64((data["updatedAt"] as? Int) ?? 0)
                let updatedByUid = (data["updatedByUid"] as? String) ?? ""
                let updatedByName = (data["updatedByName"] as? String) ?? ""

                if folderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let localUpdated = (try? loadLocalNoteUpdatedAt(noteId: noteId)) ?? 0
                if updatedAt <= localUpdated { continue }
                _ = try? upsertNote(
                    id: noteId,
                    folderId: folderId,
                    title: title,
                    content: content,
                    updatedByUid: updatedByUid,
                    updatedByName: updatedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : updatedByName
                )
            }

            let deletesSnap = try await noteDeletesCollection().getDocuments()
            for doc in deletesSnap.documents {
                let data = doc.data()
                let noteId = (data["id"] as? String) ?? doc.documentID
                if noteId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                try? deleteNote(noteId: noteId)
            }
        } catch {
            print("[PharmaRepository] syncNotesFromCloud failed: \(error)")
        }
    }

    func pushNotesToCloud(updatedByUid: String) async {
        do {
            let deletesSnap = try await noteDeletesCollection().getDocuments()
            let deletedIds: Set<String> = Set(deletesSnap.documents.compactMap { doc in
                let data = doc.data()
                let noteId = (data["id"] as? String) ?? doc.documentID
                let trimmed = noteId.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            })

            let localFolders = try listNoteFolders()
            for folder in localFolders {
                await upsertNoteFolderToCloud(
                    folderId: folder.id,
                    title: folder.title,
                    sortOrder: folder.sortOrder,
                    updatedAt: folder.updatedAt,
                    updatedByUid: folder.updatedByUid ?? updatedByUid
                )
            }

            // Push all notes from all folders.
            for folder in localFolders {
                let folderNotes = try listNotes(folderId: folder.id, query: nil)
                for note in folderNotes {
                    if deletedIds.contains(note.id) {
                        try? deleteNote(noteId: note.id)
                        continue
                    }
                    await upsertNoteToCloud(
                        noteId: note.id,
                        folderId: note.folderId,
                        title: note.title,
                        content: note.content,
                        updatedAt: note.updatedAt,
                        updatedByUid: note.updatedByUid ?? updatedByUid,
                        updatedByName: note.updatedByName
                    )
                }
            }
        } catch {
            print("[PharmaRepository] pushNotesToCloud failed: \(error)")
        }
    }
#else
    func syncNotesFromCloud() async { }
#endif

    private func legacyCardRecord(fromDrugsRow row: [String: String?]) -> [String: String?] {
        var out = row

        // Backward-compat keys used across UI
        if out["inn_name"] == nil {
            out["inn_name"] = (row["inn"] ?? nil)
        }
        if out["ua_variant_id"] == nil {
            out["ua_variant_id"] = (row["id"] ?? nil)
        }
        if out["form"] == nil {
            out["form"] = (row["dosage_forms_json"] ?? nil)
        }
        if out["strength"] == nil {
            out["strength"] = (row["strength_tokens_json"] ?? nil)
        }
        if out["rx_status"] == nil {
            out["rx_status"] = (row["registration_json"] ?? nil)
        }

        return out
    }

    private func normalize(_ string: String) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        return string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: posix)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func translitToLatin(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let latin = trimmed.applyingTransform(.toLatin, reverse: false) ?? trimmed
        let folded = latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func translitToCyrillic(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let cyr = trimmed.applyingTransform(.latinToCyrillic, reverse: false) ?? trimmed
        let folded = cyr.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct CompendiumIndex {
        let byAtc: [String: [String: String?]]
        let byInn: [String: [String: String?]]
    }

    private func ensureCompendiumImportedIntoDrugsIfNeeded() throws {
        let schema = try querySchema()
        guard schema == .newDrugs else { return }

        try sqlite.execute(
            sql: """
            CREATE TABLE IF NOT EXISTS pharma_meta (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            """,
            binds: []
        )

        let existingVersion = try sqlite.querySingleRow(
            sql: "SELECT value FROM pharma_meta WHERE key = 'compendium_import_version' LIMIT 1",
            binds: []
        )?["value"] ?? nil

        if existingVersion == compendiumImportVersion {
            return
        }

        let cols = try sqlite.queryRows(sql: "PRAGMA table_info(drugs);", binds: [])
        let existing = Set(cols.compactMap { (($0["name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        func ensureColumn(_ name: String) throws {
            if existing.contains(name.lowercased()) { return }
            try sqlite.execute(sql: "ALTER TABLE drugs ADD COLUMN \(name) TEXT;", binds: [])
        }

        try ensureColumn("compendium_id")
        try ensureColumn("compendium_brand_name")
        try ensureColumn("compendium_inn")
        try ensureColumn("compendium_atc")
        try ensureColumn("compendium_manufacturer")
        try ensureColumn("compendium_composition")
        try ensureColumn("pharmacological_properties")
        try ensureColumn("indications")
        try ensureColumn("dosage_administration")
        try ensureColumn("contraindications")
        try ensureColumn("side_effects")
        try ensureColumn("interactions")
        try ensureColumn("overdose")
        try ensureColumn("storage_conditions")
        try ensureColumn("compendium_registration")

        ensureCompendiumIndexLoaded()
        guard let idx = compendiumIndex else { return }

        let drugRows = try sqlite.queryRows(
            sql: "SELECT id, atc_code1, inn FROM drugs",
            binds: []
        )

        func innCandidates(_ raw: String) -> [String] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            let separators = CharacterSet(charactersIn: "+;/,|")
            let parts = trimmed
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.isEmpty { return [trimmed] }
            return parts
        }

        try sqlite.execute(sql: "BEGIN IMMEDIATE;", binds: [])
        do {
            for row in drugRows {
                guard let id = row["id"] ?? nil, !id.isEmpty else { continue }

                let atc = (row["atc_code1"] ?? nil) ?? ""
                let atcKey = normalizeAtcKey(atc)

                var match: [String: String?]?
                if !atcKey.isEmpty {
                    match = idx.byAtc[atcKey]
                }

                if match == nil {
                    let innRaw = (row["inn"] ?? nil) ?? ""
                    for part in innCandidates(innRaw) {
                        let key = normalizeInnKey(part)
                        if key.isEmpty { continue }
                        if let m = idx.byInn[key] {
                            match = m
                            break
                        }
                    }
                }

                guard let match else { continue }

                let compendiumId = (match["compendium_id"] ?? nil)
                let brand = (match["brand_name"] ?? nil)
                let inn = (match["inn_name"] ?? nil)
                let compAtc = (match["atc_code"] ?? nil)
                let manufacturer = (match["manufacturer"] ?? nil)
                let composition = (match["composition"] ?? nil)
                let pharmProps = (match["pharmacological_properties"] ?? nil)
                let indications = (match["indications"] ?? nil)
                let dosage = (match["dosage_administration"] ?? nil)
                let contra = (match["contraindications"] ?? nil)
                let side = (match["side_effects"] ?? nil)
                let inter = (match["interactions"] ?? nil)
                let overdose = (match["overdose"] ?? nil)
                let storage = (match["storage_conditions"] ?? nil)
                let registration = (match["registration"] ?? nil)

                try sqlite.execute(
                    sql: """
                    UPDATE drugs
                    SET compendium_id = COALESCE(compendium_id, ?),
                        compendium_brand_name = COALESCE(compendium_brand_name, ?),
                        compendium_inn = COALESCE(compendium_inn, ?),
                        compendium_atc = COALESCE(compendium_atc, ?),
                        compendium_manufacturer = COALESCE(compendium_manufacturer, ?),
                        compendium_composition = COALESCE(compendium_composition, ?),
                        pharmacological_properties = COALESCE(pharmacological_properties, ?),
                        indications = COALESCE(indications, ?),
                        dosage_administration = COALESCE(dosage_administration, ?),
                        contraindications = COALESCE(contraindications, ?),
                        side_effects = COALESCE(side_effects, ?),
                        interactions = COALESCE(interactions, ?),
                        overdose = COALESCE(overdose, ?),
                        storage_conditions = COALESCE(storage_conditions, ?),
                        compendium_registration = COALESCE(compendium_registration, ?)
                    WHERE id = ?;
                    """,
                    binds: [
                        compendiumId != nil ? .text(compendiumId!) : .null,
                        brand != nil ? .text(brand!) : .null,
                        inn != nil ? .text(inn!) : .null,
                        compAtc != nil ? .text(compAtc!) : .null,
                        manufacturer != nil ? .text(manufacturer!) : .null,
                        composition != nil ? .text(composition!) : .null,
                        pharmProps != nil ? .text(pharmProps!) : .null,
                        indications != nil ? .text(indications!) : .null,
                        dosage != nil ? .text(dosage!) : .null,
                        contra != nil ? .text(contra!) : .null,
                        side != nil ? .text(side!) : .null,
                        inter != nil ? .text(inter!) : .null,
                        overdose != nil ? .text(overdose!) : .null,
                        storage != nil ? .text(storage!) : .null,
                        registration != nil ? .text(registration!) : .null,
                        .text(id)
                    ]
                )
            }

            try sqlite.execute(
                sql: """
                INSERT INTO pharma_meta(key, value) VALUES('compendium_import_version', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """,
                binds: [.text(compendiumImportVersion)]
            )
            try sqlite.execute(
                sql: """
                INSERT INTO pharma_meta(key, value) VALUES('compendium_imported_at', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """,
                binds: [.text(String(Int64(Date().timeIntervalSince1970)))]
            )
            try sqlite.execute(sql: "COMMIT;", binds: [])
        } catch {
            try? sqlite.execute(sql: "ROLLBACK;", binds: [])
            throw error
        }
    }

    private func normalizeInnKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var k = normalize(trimmed)
        if k.hasSuffix("um") {
            k = String(k.dropLast(2))
        }
        return k
    }

    private func normalizeAtcKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func ensureCompendiumIndexLoaded() {
        if compendiumIndex != nil { return }

        let preferred = Bundle.main.url(
            forResource: "компендиум1_enriched_units_fixed_v11_kopacyl_fix",
            withExtension: "json"
        )
        guard let url = preferred else {
            compendiumIndex = CompendiumIndex(byAtc: [:], byInn: [:])
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let arr = obj as? [[String: Any]] else {
                compendiumIndex = CompendiumIndex(byAtc: [:], byInn: [:])
                return
            }

            var byAtc: [String: [String: String?]] = [:]
            var byInn: [String: [String: String?]] = [:]

            func s(_ v: Any?) -> String? {
                if let s = v as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
                return nil
            }

            for row in arr {
                let atc = s(row["ATC Code"]) ?? ""
                let inn = s(row["INN / МНН"]) ?? ""
                let brand = s(row["Brand Name"]) ?? ""
                let manufacturer = s(row["Manufacturer"]) ?? ""
                let composition = s(row["Composition"]) ?? ""

                var out: [String: String?] = [:]
                out["compendium_id"] = s(row["id"])
                out["brand_name"] = brand
                out["inn_name"] = inn
                out["atc_code"] = atc
                out["manufacturer"] = manufacturer
                out["composition"] = composition

                out["pharmacological_properties"] = s(row["Pharmacological properties"])
                out["indications"] = s(row["Indications"])
                out["dosage_administration"] = s(row["Dosage & Administration"])
                out["contraindications"] = s(row["Contraindications"])
                out["side_effects"] = s(row["Side Effects"])
                out["interactions"] = s(row["Interactions"])
                out["overdose"] = s(row["Overdose"])
                out["storage_conditions"] = s(row["Storage Conditions"])

                if let reg = row["Registration"] as? [Any] {
                    let parts = reg.compactMap { $0 as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if !parts.isEmpty {
                        out["registration"] = parts.joined(separator: "\n")
                    }
                }

                let atcKey = normalizeAtcKey(atc)
                if !atcKey.isEmpty, byAtc[atcKey] == nil {
                    byAtc[atcKey] = out
                }

                let innKey = normalizeInnKey(inn)
                if !innKey.isEmpty, byInn[innKey] == nil {
                    byInn[innKey] = out
                }
            }

            compendiumIndex = CompendiumIndex(byAtc: byAtc, byInn: byInn)
        } catch {
            compendiumIndex = CompendiumIndex(byAtc: [:], byInn: [:])
        }
    }

    private func compendiumEnrichment(for drugRow: [String: String?]) -> [String: String?]? {
        ensureCompendiumIndexLoaded()
        guard let idx = compendiumIndex else { return nil }

        let atc = (drugRow["atc_code1"] ?? nil) ?? ""
        let atcKey = normalizeAtcKey(atc)
        if !atcKey.isEmpty, let match = idx.byAtc[atcKey] {
            return match
        }

        let inn = (drugRow["inn"] ?? nil) ?? ""
        let innKey = normalizeInnKey(inn)
        if !innKey.isEmpty, let match = idx.byInn[innKey] {
            return match
        }

        return nil
    }

    private func querySchema() throws -> DatabaseSchema {
        if let schema { return schema }

        // Prefer new schema if present.
        let row = try sqlite.querySingleRow(
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='drugs' LIMIT 1",
            binds: []
        )
        let detected: DatabaseSchema = (row?["name"] ?? nil) == "drugs" ? .newDrugs : .legacy
        self.schema = detected
        return detected
    }

    private func ensureIndexLoaded() async throws {
        if index != nil { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let schema = try self.querySchema()

                    let indexSql: String
                    switch schema {
                    case .newDrugs:
                        indexSql = """
                        SELECT d.id,
                               COALESCE(d.brand_name_ua, '') AS brand_name_ua,
                               COALESCE(d.inn, '') AS inn,
                               COALESCE(d.dosage_form_text, '') AS dosage_form_text,
                               COALESCE(d.dispensing_conditions, '') AS dispensing_conditions,
                               COALESCE(d.composition_actives, '') AS composition_actives,
                               COALESCE(d.manufacturer1_ua, '') AS manufacturer1_ua,
                               COALESCE(d.applicant_ua, '') AS applicant_ua,
                               COALESCE(d.registry, '') AS registry,
                               CASE
                                   WHEN ura.ua_variant_id IS NULL THEN 0
                                   WHEN COALESCE(ura.dose_text, '') != '' THEN 1
                                   WHEN COALESCE(ura.quantity_n, '') != '' THEN 1
                                   WHEN COALESCE(ura.form_raw, '') != '' THEN 1
                                   WHEN COALESCE(ura.signa_text, '') != '' THEN 1
                                   ELSE 0
                               END AS is_annotated
                        FROM drugs d
                        LEFT JOIN user_recipe_annotations ura ON ura.ua_variant_id = d.id
                        ORDER BY d.brand_name_ua
                        """
                    case .legacy:
                        indexSql = """
                        SELECT fr.ua_variant_id,
                               COALESCE(fr.brand_name, '') AS brand_name,
                               COALESCE(fr.inn_name, '') AS inn_name,
                               COALESCE(urv.manufacturer, '') AS manufacturer,
                               COALESCE(fr.instruction_source, '') AS source,
                               COALESCE(urv.form, '') AS form,
                               COALESCE(urv.composition, '') AS composition,
                               CASE
                                   WHEN ura.ua_variant_id IS NULL THEN 0
                                   WHEN COALESCE(ura.dose_text, '') != '' THEN 1
                                   WHEN COALESCE(ura.quantity_n, '') != '' THEN 1
                                   WHEN COALESCE(ura.form_raw, '') != '' THEN 1
                                   WHEN COALESCE(ura.signa_text, '') != '' THEN 1
                                   ELSE 0
                               END AS is_annotated
                        FROM FINAL_RECORDS fr
                        LEFT JOIN ua_registry_variant urv ON urv.ua_variant_id = fr.ua_variant_id
                        LEFT JOIN user_recipe_annotations ura ON ura.ua_variant_id = fr.ua_variant_id
                        ORDER BY fr.brand_name
                        """
                    }

                    let rows = try self.sqlite.queryRows(
                        sql: indexSql,
                        binds: []
                    )

                    print("PharmaRepository index source rows:", rows.count)

                    let built: [(DrugSearchResult, String)] = rows.compactMap { row -> (DrugSearchResult, String)? in
                        let uaVariantId: String
                        let brand: String
                        let inn: String
                        let manufacturer: String
                        let source: String
                        let dosageFormText: String
                        let compositionActives: String
                        let dispensingConditions: String
                        let registry: String

                        switch schema {
                        case .newDrugs:
                            guard let id = row["id"] ?? nil, !id.isEmpty else { return nil }
                            uaVariantId = id
                            brand = (row["brand_name_ua"] ?? nil) ?? ""
                            inn = (row["inn"] ?? nil) ?? ""
                            let m1 = (row["manufacturer1_ua"] ?? nil) ?? ""
                            let app = (row["applicant_ua"] ?? nil) ?? ""
                            manufacturer = !m1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? m1 : app
                            source = "PHARMA_BASE3"
                            dosageFormText = (row["dosage_form_text"] ?? nil) ?? ""
                            compositionActives = (row["composition_actives"] ?? nil) ?? ""
                            dispensingConditions = (row["dispensing_conditions"] ?? nil) ?? ""
                            registry = (row["registry"] ?? nil) ?? ""
                        case .legacy:
                            guard let id = row["ua_variant_id"] ?? nil, !id.isEmpty else { return nil }
                            uaVariantId = id
                            brand = (row["brand_name"] ?? nil) ?? ""
                            inn = (row["inn_name"] ?? nil) ?? ""
                            manufacturer = (row["manufacturer"] ?? nil) ?? ""
                            source = (row["source"] ?? nil) ?? ""
                            dosageFormText = (row["form"] ?? nil) ?? ""
                            compositionActives = (row["composition"] ?? nil) ?? ""
                            dispensingConditions = ""
                            registry = ""
                        }

                        let rxStatus = dispensingConditions
                        let isAnnotated = ((row["is_annotated"] ?? nil) ?? "0") == "1"

                        let formAndComposition = (dosageFormText + " " + compositionActives).trimmingCharacters(in: .whitespacesAndNewlines)
                        let dose = RecipeParsing.extractDose(from: formAndComposition)
                        let n = RecipeParsing.extractQuantityN(from: formAndComposition)
                        let parts = [
                            dosageFormText.trimmingCharacters(in: .whitespacesAndNewlines),
                            dose.trimmingCharacters(in: .whitespacesAndNewlines),
                            n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "№\(n)",
                            compositionActives.trimmingCharacters(in: .whitespacesAndNewlines)
                        ].filter { !$0.isEmpty }
                        let formDoseLine = parts.joined(separator: " · ")

                        let result = DrugSearchResult(
                            uaVariantId: uaVariantId,
                            brandName: brand,
                            innName: inn,
                            composition: compositionActives,
                            manufacturer: manufacturer,
                            source: source,
                            formDoseLine: formDoseLine,
                            rxStatus: rxStatus,
                            isAnnotated: isAnnotated,
                            registry: registry,
                            dosageFormText: dosageFormText,
                            dispensingConditions: dispensingConditions
                        )

                        let base = (brand + " " + inn + " " + compositionActives + " " + manufacturer + " " + uaVariantId)
                        let t1 = self.normalize(base)
                        let t2 = self.normalize(self.translitToLatin(base))
                        let t3 = self.normalize(self.translitToCyrillic(base))
                        let text = (t1 + " " + t2 + " " + t3).trimmingCharacters(in: .whitespacesAndNewlines)
                        return (result, text)
                    }

                    print("PharmaRepository index built:", built.count)

                    if built.isEmpty {
                        continuation.resume(throwing: SQLiteServiceError.stepFailed("Search index is empty. Check DB schema/tables and contents. DB: \(self.dbPath)"))
                        return
                    }

                    let sortedBuilt = built.sorted { a, b in
                        if a.0.isAnnotated != b.0.isAnnotated {
                            return a.0.isAnnotated && !b.0.isAnnotated
                        }
                        if a.0.sourcePriority != b.0.sourcePriority {
                            return a.0.sourcePriority < b.0.sourcePriority
                        }

                        let an = self.normalize(a.0.brandName)
                        let bn = self.normalize(b.0.brandName)
                        if an != bn { return an < bn }

                        return a.0.uaVariantId < b.0.uaVariantId
                    }

                    self.index = sortedBuilt
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func search(query: String, limit: Int = 50, registryScope: RegistryScope = .all) async throws -> [DrugSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let ftsResults = await searchFTS(query: trimmed, limit: limit, registryScope: registryScope)
        if !ftsResults.isEmpty {
            return ftsResults
        }

        try await ensureIndexLoaded()
        guard let index else { return [] }

        let normalizedQuery = normalize(trimmed)
        let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map { String($0) }.filter { !$0.isEmpty }
        let translitQuery = translitToLatin(trimmed)
        let translitTerms = translitQuery.split(whereSeparator: { $0.isWhitespace }).map { String($0) }.filter { !$0.isEmpty }
        let cyrQuery = translitToCyrillic(trimmed)
        let cyrTerms = cyrQuery.split(whereSeparator: { $0.isWhitespace }).map { String($0) }.filter { !$0.isEmpty }
        if terms.isEmpty { return [] }

        var candidates: [DrugSearchResult] = []
        let maxCandidates = max(limit * 20, 400)
        candidates.reserveCapacity(min(maxCandidates, 600))

        for item in index {
            let okOriginal = terms.allSatisfy { item.searchText.contains($0) }
            let okTranslit = !translitTerms.isEmpty && translitTerms.allSatisfy { item.searchText.contains($0) }
            let okCyr = !cyrTerms.isEmpty && cyrTerms.allSatisfy { item.searchText.contains($0) }
            if okOriginal || okTranslit || okCyr {
                candidates.append(item.result)
                if candidates.count >= maxCandidates { break }
            }
        }

        if registryScope != .all {
            let needed = registryScope.dbValue
            candidates = candidates.filter { $0.registry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == needed }
        }

        candidates.sort { a, b in
            if a.isAnnotated != b.isAnnotated { return a.isAnnotated && !b.isAnnotated }
            if a.sourcePriority != b.sourcePriority { return a.sourcePriority < b.sourcePriority }
            if a.completenessScore != b.completenessScore { return a.completenessScore > b.completenessScore }

            let an = self.normalize(a.brandName)
            let bn = self.normalize(b.brandName)
            if an != bn { return an < bn }

            return a.uaVariantId < b.uaVariantId
        }

        return Array(candidates.prefix(limit))
    }

    func defaultDrugs(limit: Int = 10) async throws -> [DrugSearchResult] {
        try await ensureIndexLoaded()
        guard let index else { return [] }
        return Array(index.prefix(max(0, limit))).map { $0.result }
    }

    private func makeFTSQuery(from userInput: String) -> String {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // If user already wrote an advanced query (operators/quotes), do not rewrite.
        let lowered = trimmed.lowercased()
        if trimmed.contains("\"") || lowered.contains(" or ") || lowered.contains(" and ") || trimmed.contains(":") || trimmed.contains("*") {
            return trimmed
        }

        // Basic query: AND terms with prefix matching.
        let normalizedQuery = normalize(trimmed)
        let terms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if terms.isEmpty { return "" }
        return terms.map { "\($0)*" }.joined(separator: " AND ")
    }

    private func searchFTS(query: String, limit: Int, registryScope: RegistryScope) async -> [DrugSearchResult] {
        let primary = makeFTSQuery(from: query)
        let latin = makeFTSQuery(from: translitToLatin(query))
        let cyr = makeFTSQuery(from: translitToCyrillic(query))
        let candidates = [primary, latin, cyr].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !candidates.isEmpty else { return [] }

        let normalizedQuery = normalize(query)
        let normalizedLatin = normalize(translitToLatin(query))
        let normalizedCyr = normalize(translitToCyrillic(query))
        let normalizedVariants = [normalizedQuery, normalizedLatin, normalizedCyr].filter { !$0.isEmpty }

        return await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let schema = try self.querySchema()

                    func parseTokenArray(_ raw: String) -> [String] {
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return [] }
                        guard let data = trimmed.data(using: .utf8) else { return [] }
                        if let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any] {
                            return arr
                                .compactMap { $0 as? String }
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                        return []
                    }

                    var allRows: [[String: String?]] = []
                    let perQueryLimit = max(limit * 5, 100)
                    allRows.reserveCapacity(max(1, min(perQueryLimit, 500)))

                    for q in candidates {
                        let ftsSql: String
                        switch schema {
                        case .newDrugs:
                            ftsSql = """
                            SELECT CAST(d.id AS TEXT) AS id,
                                   COALESCE(d.brand_name_ua, '') AS brand_name_ua,
                                   COALESCE(d.inn, '') AS inn,
                                   COALESCE(d.dosage_form_text, '') AS dosage_form_text,
                                   COALESCE(d.dispensing_conditions, '') AS dispensing_conditions,
                                   COALESCE(d.composition_actives, '') AS composition_actives,
                                   COALESCE(d.manufacturer1_ua, '') AS manufacturer1_ua,
                                   COALESCE(d.applicant_ua, '') AS applicant_ua,
                                   COALESCE(d.registry, '') AS registry,
                                   CASE
                                       WHEN ura.ua_variant_id IS NULL THEN 0
                                       WHEN COALESCE(ura.dose_text, '') != '' THEN 1
                                       WHEN COALESCE(ura.quantity_n, '') != '' THEN 1
                                       WHEN COALESCE(ura.form_raw, '') != '' THEN 1
                                       WHEN COALESCE(ura.signa_text, '') != '' THEN 1
                                       ELSE 0
                                   END AS is_annotated
                            FROM drugs_fts f
                            JOIN drugs d ON d.id = f.rowid
                            LEFT JOIN user_recipe_annotations ura ON ura.ua_variant_id = d.id
                            WHERE drugs_fts MATCH ?
                            LIMIT ?
                            """
                        case .legacy:
                            ftsSql = """
                            SELECT fr.ua_variant_id,
                                   COALESCE(fr.brand_name, '') AS brand_name,
                                   COALESCE(fr.inn_name, '') AS inn_name,
                                   COALESCE(urv.manufacturer, '') AS manufacturer,
                                   COALESCE(fr.instruction_source, '') AS source,
                                   COALESCE(urv.form, '') AS form,
                                   COALESCE(urv.composition, '') AS composition,
                                   CASE
                                       WHEN ura.ua_variant_id IS NULL THEN 0
                                       WHEN COALESCE(ura.dose_text, '') != '' THEN 1
                                       WHEN COALESCE(ura.quantity_n, '') != '' THEN 1
                                       WHEN COALESCE(ura.form_raw, '') != '' THEN 1
                                       WHEN COALESCE(ura.signa_text, '') != '' THEN 1
                                       ELSE 0
                                   END AS is_annotated
                            FROM fts_all f
                            JOIN FINAL_RECORDS fr ON fr.ua_variant_id = f.ref_id
                            LEFT JOIN ua_registry_variant urv ON urv.ua_variant_id = fr.ua_variant_id
                            LEFT JOIN user_recipe_annotations ura ON ura.ua_variant_id = fr.ua_variant_id
                            WHERE fts_all MATCH ?
                              AND f.kind = 'variant'
                            LIMIT ?
                            """
                        }

                        let rows: [[String: String?]]
                        switch schema {
                        case .newDrugs:
                            rows = try self.sqlite.queryRows(
                                sql: ftsSql,
                                binds: [.text(q), .int(Int64(max(1, perQueryLimit)))]
                            )
                        case .legacy:
                            rows = try self.sqlite.queryRows(
                                sql: ftsSql,
                                binds: [.text(q), .int(Int64(max(1, perQueryLimit)))]
                            )
                        }

                        for r in rows {
                            allRows.append(r)
                            if allRows.count >= perQueryLimit { break }
                        }
                        if allRows.count >= perQueryLimit { break }
                    }

                    var seen = Set<String>()
                    var results: [DrugSearchResult] = []
                    results.reserveCapacity(min(allRows.count, perQueryLimit))

                    for row in allRows {
                        let uaVariantId: String
                        let brand: String
                        let inn: String
                        let manufacturer: String
                        let source: String
                        let dosageFormText: String
                        let compositionActives: String
                        let dispensingConditions: String
                        let registry: String

                        switch schema {
                        case .newDrugs:
                            guard let id = row["id"] ?? nil, !id.isEmpty else { continue }
                            uaVariantId = id
                            brand = (row["brand_name_ua"] ?? nil) ?? ""
                            inn = (row["inn"] ?? nil) ?? ""
                            let m1 = (row["manufacturer1_ua"] ?? nil) ?? ""
                            let app = (row["applicant_ua"] ?? nil) ?? ""
                            manufacturer = !m1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? m1 : app
                            source = "PHARMA_BASE3"
                            dosageFormText = (row["dosage_form_text"] ?? nil) ?? ""
                            compositionActives = (row["composition_actives"] ?? nil) ?? ""
                            dispensingConditions = (row["dispensing_conditions"] ?? nil) ?? ""
                            registry = (row["registry"] ?? nil) ?? ""
                        case .legacy:
                            guard let id = row["ua_variant_id"] ?? nil, !id.isEmpty else { continue }
                            uaVariantId = id
                            brand = (row["brand_name"] ?? nil) ?? ""
                            inn = (row["inn_name"] ?? nil) ?? ""
                            manufacturer = (row["manufacturer"] ?? nil) ?? ""
                            source = (row["source"] ?? nil) ?? ""
                            dosageFormText = (row["form"] ?? nil) ?? ""
                            compositionActives = (row["composition"] ?? nil) ?? ""
                            dispensingConditions = ""
                            registry = ""
                        }
                        if seen.contains(uaVariantId) { continue }
                        seen.insert(uaVariantId)
                        let isAnnotated = ((row["is_annotated"] ?? nil) ?? "0") == "1"

                        let formDoseLine: String
                        switch schema {
                        case .newDrugs:
                            let formAndComposition = (dosageFormText + " " + compositionActives).trimmingCharacters(in: .whitespacesAndNewlines)
                            let dose = RecipeParsing.extractDose(from: formAndComposition)
                            let n = RecipeParsing.extractQuantityN(from: formAndComposition)
                            let parts = [
                                dosageFormText.trimmingCharacters(in: .whitespacesAndNewlines),
                                dose.trimmingCharacters(in: .whitespacesAndNewlines),
                                n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "№\(n)",
                                compositionActives.trimmingCharacters(in: .whitespacesAndNewlines)
                            ].filter { !$0.isEmpty }
                            formDoseLine = parts.joined(separator: " · ")
                        case .legacy:
                            let formAndComposition = (dosageFormText + " " + compositionActives).trimmingCharacters(in: .whitespacesAndNewlines)
                            let dose = RecipeParsing.extractDose(from: formAndComposition)
                            let n = RecipeParsing.extractQuantityN(from: formAndComposition)
                            formDoseLine = ([
                                dosageFormText.trimmingCharacters(in: .whitespacesAndNewlines),
                                dose.trimmingCharacters(in: .whitespacesAndNewlines),
                                n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "№\(n)"
                            ].filter { !$0.isEmpty }).joined(separator: " ")
                        }

                        let result = DrugSearchResult(
                            uaVariantId: uaVariantId,
                            brandName: brand,
                            innName: inn,
                            composition: compositionActives,
                            manufacturer: manufacturer,
                            source: source,
                            formDoseLine: formDoseLine,
                            rxStatus: dispensingConditions,
                            isAnnotated: isAnnotated,
                            registry: registry,
                            dosageFormText: dosageFormText,
                            dispensingConditions: dispensingConditions
                        )

                        results.append(result)
                        if results.count >= perQueryLimit { break }
                    }

                    // Prioritize exact/near-exact matches so mono-drugs don't get pushed out by long "contains" matches.
                    results.sort { a, b in
                        func score(_ r: DrugSearchResult) -> Int {
                            let bn = self.normalize(r.brandName)
                            let inn = self.normalize(r.innName)
                            if normalizedVariants.contains(inn) { return 0 }
                            if normalizedVariants.contains(bn) { return 1 }
                            if normalizedVariants.contains(where: { !inn.isEmpty && inn.contains($0) }) { return 2 }
                            if normalizedVariants.contains(where: { !bn.isEmpty && bn.contains($0) }) { return 3 }
                            return 10
                        }

                        let sa = score(a)
                        let sb = score(b)
                        if sa != sb { return sa < sb }

                        if a.isAnnotated != b.isAnnotated { return a.isAnnotated && !b.isAnnotated }
                        if a.sourcePriority != b.sourcePriority { return a.sourcePriority < b.sourcePriority }
                        if a.completenessScore != b.completenessScore { return a.completenessScore > b.completenessScore }

                        let an = self.normalize(a.brandName)
                        let bn = self.normalize(b.brandName)
                        if an != bn { return an < bn }
                        return a.uaVariantId < b.uaVariantId
                    }

                    continuation.resume(returning: Array(results.prefix(limit)))
                } catch {
                    // If MATCH syntax fails or table missing – silently fallback.
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Compendium (new DB)

    private func compendiumAnnotatedSet(for ids: [String]) throws -> Set<String> {
        let trimmedIds = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmedIds.isEmpty { return [] }

        let placeholders = Array(repeating: "?", count: trimmedIds.count).joined(separator: ",")
        let sql = "SELECT ua_variant_id FROM user_recipe_annotations WHERE ua_variant_id IN (\(placeholders));"
        let binds: [SQLiteValue] = trimmedIds.map { .text($0) }
        let rows = try self.sqlite.queryRows(sql: sql, binds: binds)
        let set = Set(rows.compactMap { ($0["ua_variant_id"] ?? nil) })
        return set
    }

    private func compendiumSearchResult(from hit: CompendiumHit, isAnnotated: Bool) -> DrugSearchResult {
        return DrugSearchResult(
            uaVariantId: hit.id,
            brandName: hit.brandName ?? "",
            innName: hit.inn ?? "",
            composition: "",
            manufacturer: "",
            source: "COMPENDIUM",
            formDoseLine: "",
            rxStatus: "",
            isAnnotated: isAnnotated,
            registry: "",
            dosageFormText: "",
            dispensingConditions: ""
        )
    }

    private func compendiumCard(from item: CompendiumItemDetails) -> DrugCard {
        var record: [String: String?] = [
            "id": item.id,
            "brand_name": item.brandName,
            "inn": item.inn,
            "atc_code": item.atcCode,
            "composition": item.composition,
            "pharmacological_properties": item.pharmacologicalProperties,
            "indications": item.indications,
            "dosage_administration": item.dosageAdministration,
            "contraindications": item.contraindications,
            "side_effects": item.sideEffects,
            "interactions": item.interactions,
            "overdose": item.overdose,
            "storage_conditions": item.storageConditions
        ]

        // Compatibility keys used by existing UI
        if record["dosage_form_text"] == nil {
            record["dosage_form_text"] = nil
        }
        if record["composition_actives"] == nil {
            record["composition_actives"] = item.composition
        }

        return DrugCard(
            uaVariantId: item.id,
            finalRecord: record,
            uaRegistryVariant: nil,
            enrichedVariant: nil
        )
    }

    private func loadCompendiumCard(uaVariantId: String) throws -> DrugCard? {
        guard let item = try CompendiumSQLiteService.shared.fetchItem(id: uaVariantId) else { return nil }
        return compendiumCard(from: item)
    }

    func searchCompendium(query: String, limit: Int = 50) async throws -> [DrugSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[DrugSearchResult], Error>) in
            queue.async {
                do {
                    let items = try CompendiumSQLiteService.shared.searchFTS(trimmed, limit: limit)
                    let annotated = try self.compendiumAnnotatedSet(for: items.map { $0.id })
                    let results = items.map { self.compendiumSearchResult(from: $0, isAnnotated: annotated.contains($0.id)) }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func defaultCompendiumDrugs(limit: Int = 10) async throws -> [DrugSearchResult] {
        return []
    }

    func loadCard(uaVariantId: String) async throws -> DrugCard {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DrugCard, Error>) in
            queue.async {
                do {
                    let schema = try self.querySchema()

                    switch schema {
                    case .newDrugs:
                        guard let drugsRow = try self.sqlite.querySingleRow(
                            sql: "SELECT * FROM drugs WHERE id = ? LIMIT 1",
                            binds: [.text(uaVariantId)]
                        ) else {
                            if let compendium = try self.loadCompendiumCard(uaVariantId: uaVariantId) {
                                continuation.resume(returning: compendium)
                                return
                            }
                            throw SQLiteServiceError.stepFailed("Drug not found in drugs for id=\(uaVariantId)")
                        }

                        let finalRecord = drugsRow
                        let enriched = self.compendiumEnrichment(for: drugsRow)
                        continuation.resume(returning: DrugCard(
                            uaVariantId: uaVariantId,
                            finalRecord: finalRecord,
                            uaRegistryVariant: nil,
                            enrichedVariant: enriched
                        ))

                    case .legacy:
                        guard let finalRecord = try self.sqlite.querySingleRow(
                            sql: "SELECT * FROM FINAL_RECORDS WHERE ua_variant_id = ? LIMIT 1",
                            binds: [.text(uaVariantId)]
                        ) else {
                            if let compendium = try self.loadCompendiumCard(uaVariantId: uaVariantId) {
                                continuation.resume(returning: compendium)
                                return
                            }
                            throw SQLiteServiceError.stepFailed("Drug not found in FINAL_RECORDS for ua_variant_id=\(uaVariantId)")
                        }

                        let uaRegistry = try self.sqlite.querySingleRow(
                            sql: "SELECT * FROM ua_registry_variant WHERE ua_variant_id = ? LIMIT 1",
                            binds: [.text(uaVariantId)]
                        )

                        let enriched = try self.sqlite.querySingleRow(
                            sql: "SELECT * FROM enriched_variant WHERE ua_variant_id = ? LIMIT 1",
                            binds: [.text(uaVariantId)]
                        )

                        continuation.resume(returning: DrugCard(
                            uaVariantId: uaVariantId,
                            finalRecord: finalRecord,
                            uaRegistryVariant: uaRegistry,
                            enrichedVariant: enriched
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadUserRecipeAnnotation(uaVariantId: String) async throws -> [String: String?]? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String?]?, Error>) in
            queue.async {
                do {
                    let row = try self.sqlite.querySingleRow(
                        sql: """
                        SELECT dose_text, quantity_n, form_raw, signa_text, volume_text
                        FROM user_recipe_annotations
                        WHERE ua_variant_id = ?
                        LIMIT 1
                        """,
                        binds: [.text(uaVariantId)]
                    )
                    continuation.resume(returning: row)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveUserRecipeAnnotation(
        uaVariantId: String,
        doseText: String? = nil,
        quantityN: String? = nil,
        formRaw: String? = nil,
        signaText: String? = nil,
        volumeText: String? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let now = Int64(Date().timeIntervalSince1970)
                    try self.sqlite.execute(
                        sql: """
                        INSERT INTO user_recipe_annotations (ua_variant_id, dose_text, quantity_n, form_raw, signa_text, volume_text, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(ua_variant_id) DO UPDATE SET
                            dose_text = COALESCE(excluded.dose_text, user_recipe_annotations.dose_text),
                            quantity_n = COALESCE(excluded.quantity_n, user_recipe_annotations.quantity_n),
                            form_raw = COALESCE(excluded.form_raw, user_recipe_annotations.form_raw),
                            signa_text = COALESCE(excluded.signa_text, user_recipe_annotations.signa_text),
                            volume_text = COALESCE(excluded.volume_text, user_recipe_annotations.volume_text),
                            updated_at = excluded.updated_at;
                        """,
                        binds: [
                            .text(uaVariantId),
                            doseText != nil ? .text(doseText!) : .null,
                            quantityN != nil ? .text(quantityN!) : .null,
                            formRaw != nil ? .text(formRaw!) : .null,
                            signaText != nil ? .text(signaText!) : .null,
                            volumeText != nil ? .text(volumeText!) : .null,
                            .int(now)
                        ]
                    )

                    if let idx = self.index {
                        self.index = idx.map { item in
                            if item.result.uaVariantId != uaVariantId { return item }
                            if item.result.isAnnotated { return item }
                            let updated = DrugSearchResult(
                                uaVariantId: item.result.uaVariantId,
                                brandName: item.result.brandName,
                                innName: item.result.innName,
                                composition: item.result.composition,
                                manufacturer: item.result.manufacturer,
                                source: item.result.source,
                                formDoseLine: item.result.formDoseLine,
                                rxStatus: item.result.rxStatus,
                                isAnnotated: true,
                                registry: item.result.registry,
                                dosageFormText: item.result.dosageFormText,
                                dispensingConditions: item.result.dispensingConditions
                            )
                            return (updated, item.searchText)
                        }
                    }

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        Task {
            await self.upsertUserRecipeAnnotationToCloud(
                uaVariantId: uaVariantId,
                doseText: doseText,
                quantityN: quantityN,
                formRaw: formRaw,
                signaText: signaText
            )

            await self.upsertSharedRecipeToCloud(
                uaVariantId: uaVariantId,
                doseText: doseText,
                quantityN: quantityN,
                formRaw: formRaw,
                signaText: signaText
            )
        }
#endif
    }

#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
    private func listLocalUserRecipeAnnotations() throws -> [[String: String?]] {
        try queueSync {
            try self.sqlite.queryRows(
                sql: """
                SELECT ua_variant_id, COALESCE(dose_text, '') AS dose_text, COALESCE(quantity_n, '') AS quantity_n,
                       COALESCE(form_raw, '') AS form_raw, COALESCE(signa_text, '') AS signa_text
                FROM user_recipe_annotations
                """,
                binds: []
            )
        }
    }

    func pushLocalSharedRecipesToCloud() async {
        do {
            let rows = try listLocalUserRecipeAnnotations()
            for row in rows {
                let uaVariantId = ((row["ua_variant_id"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if uaVariantId.isEmpty { continue }

                let doseText = (row["dose_text"] ?? nil)
                let quantityN = (row["quantity_n"] ?? nil)
                let formRaw = (row["form_raw"] ?? nil)
                let signaText = (row["signa_text"] ?? nil)

                let hasAny = !(doseText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(quantityN ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(formRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(signaText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hasAny { continue }

                await upsertSharedRecipeToCloud(
                    uaVariantId: uaVariantId,
                    doseText: doseText,
                    quantityN: quantityN,
                    formRaw: formRaw,
                    signaText: signaText
                )
            }
        } catch {
            print("[PharmaRepository] pushLocalSharedRecipesToCloud failed: \(error)")
        }
    }

    private func sharedRecipeMainDoc(uaVariantId: String) -> DocumentReference {
        Firestore.firestore()
            .collection("drugs")
            .document(uaVariantId)
            .collection("shared_recipe")
            .document("main")
    }

    private func sharedRecipeRevisionsCollection(uaVariantId: String) -> CollectionReference {
        Firestore.firestore()
            .collection("drugs")
            .document(uaVariantId)
            .collection("shared_recipe")
            .document("main")
            .collection("revisions")
    }

    private func upsertUserRecipeAnnotationToCloud(
        uaVariantId: String,
        doseText: String?,
        quantityN: String?,
        formRaw: String?,
        signaText: String?
    ) async {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid

        let doc = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("recipe_annotations")
            .document(uaVariantId)

        var data: [String: Any] = [
            "updated_at": Timestamp(date: Date())
        ]

        if let doseText { data["dose_text"] = doseText }
        if let quantityN { data["quantity_n"] = quantityN }
        if let formRaw { data["form_raw"] = formRaw }
        if let signaText { data["signa_text"] = signaText }

        do {
            try await doc.setData(data, merge: true)
        } catch {
            print("[PharmaRepository] upsertUserRecipeAnnotationToCloud failed: \(error)")
        }
    }

    private func upsertSharedRecipeToCloud(
        uaVariantId: String,
        doseText: String?,
        quantityN: String?,
        formRaw: String?,
        signaText: String?
    ) async {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid

        var data: [String: Any] = [
            "updated_at": Timestamp(date: Date()),
            "updated_by_uid": uid
        ]
        if let doseText { data["dose_text"] = doseText }
        if let quantityN { data["quantity_n"] = quantityN }
        if let formRaw { data["form_raw"] = formRaw }
        if let signaText { data["signa_text"] = signaText }

        do {
            try await sharedRecipeMainDoc(uaVariantId: uaVariantId).setData(data, merge: true)

            var rev = data
            rev["created_at"] = Timestamp(date: Date())
            rev["created_by_uid"] = uid
            try await sharedRecipeRevisionsCollection(uaVariantId: uaVariantId).addDocument(data: rev)
        } catch {
            print("[PharmaRepository] upsertSharedRecipeToCloud failed: \(error)")
        }
    }

    func loadSharedRecipeFromCloud(uaVariantId: String) async -> [String: Any]? {
        do {
            let doc = try await sharedRecipeMainDoc(uaVariantId: uaVariantId).getDocument()
            return doc.data()
        } catch {
            print("[PharmaRepository] loadSharedRecipeFromCloud failed: \(error)")
            return nil
        }
    }

    private func wikiTitleForDrug(uaVariantId: String) -> String {
        do {
            let schema = try querySchema()
            let row: [String: String?]?
            switch schema {
            case .newDrugs:
                row = try sqlite.querySingleRow(
                    sql: """
                    SELECT COALESCE(brand_name, '') AS brand_name, COALESCE(inn, '') AS inn
                    FROM drugs
                    WHERE id = ?
                    LIMIT 1;
                    """,
                    binds: [.text(uaVariantId)]
                )
                let brand = ((row?["brand_name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let inn = ((row?["inn"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !brand.isEmpty, !inn.isEmpty { return "\(brand) — \(inn)" }
                if !brand.isEmpty { return brand }
                if !inn.isEmpty { return inn }
                return uaVariantId
            case .legacy:
                row = try sqlite.querySingleRow(
                    sql: """
                    SELECT COALESCE(brand_name, '') AS brand_name, COALESCE(inn_name, '') AS inn_name
                    FROM FINAL_RECORDS
                    WHERE ua_variant_id = ?
                    LIMIT 1;
                    """,
                    binds: [.text(uaVariantId)]
                )
                let brand = ((row?["brand_name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let inn = ((row?["inn_name"] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !brand.isEmpty, !inn.isEmpty { return "\(brand) — \(inn)" }
                if !brand.isEmpty { return brand }
                if !inn.isEmpty { return inn }
                return uaVariantId
            }
        } catch {
            return uaVariantId
        }
    }

    func listSharedRecipesFromCloud(searchQuery: String? = nil, limit: Int = 200) async throws -> [WikiRecipeItem] {
        let q = (searchQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let snap = try await Firestore.firestore()
            .collectionGroup("shared_recipe")
            .limit(to: max(1, min(limit, 500)))
            .getDocuments()

        var items: [WikiRecipeItem] = []
        items.reserveCapacity(min(snap.documents.count, limit))

        for doc in snap.documents {
            if doc.documentID != "main" { continue }
            guard let uaVariantId = doc.reference.parent.parent?.documentID else { continue }
            let data = doc.data()

            let doseText = (data["dose_text"] as? String) ?? ""
            let quantityN = (data["quantity_n"] as? String) ?? ""
            let formRaw = (data["form_raw"] as? String) ?? ""
            let signaText = (data["signa_text"] as? String) ?? ""

            // If a shared recipe is completely empty, skip it.
            let hasAny = !doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !quantityN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !formRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasAny { continue }

            let updatedByUid = (data["updated_by_uid"] as? String) ?? ""
            let updatedAt = (data["updated_at"] as? Timestamp)?.dateValue()

            let title = try queueSync {
                self.wikiTitleForDrug(uaVariantId: uaVariantId)
            }

            let item = WikiRecipeItem(
                uaVariantId: uaVariantId,
                title: title,
                doseText: doseText,
                quantityN: quantityN,
                formRaw: formRaw,
                signaText: signaText,
                updatedByUid: updatedByUid,
                updatedAt: updatedAt
            )

            if !q.isEmpty {
                let hay = (title + " " + doseText + " " + quantityN + " " + formRaw + " " + signaText + " " + uaVariantId).lowercased()
                if !hay.contains(q) { continue }
            }

            items.append(item)
            if items.count >= limit { break }
        }

        items.sort { a, b in
            let ad = a.updatedAt ?? Date(timeIntervalSince1970: 0)
            let bd = b.updatedAt ?? Date(timeIntervalSince1970: 0)
            if ad != bd { return ad > bd }
            return a.title < b.title
        }

        return items
    }

    func syncUserRecipeAnnotationsFromCloud(userId: String) async {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != UserSessionStore.defaultUserId else { return }
        guard let current = Auth.auth().currentUser, current.uid == trimmed else { return }

        do {
            print("[PharmaRepository] syncUserRecipeAnnotationsFromCloud start uid=\(current.uid)")
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(current.uid)
                .collection("recipe_annotations")
                .getDocuments()

            print("[PharmaRepository] syncUserRecipeAnnotationsFromCloud docs=\(snapshot.documents.count)")

            for doc in snapshot.documents {
                let uaVariantId = doc.documentID
                let data = doc.data()

                let cloudUpdatedAt: Int64 = {
                    if let ts = data["updated_at"] as? Timestamp {
                        return Int64(ts.dateValue().timeIntervalSince1970)
                    }
                    return 0
                }()

                let localUpdatedAt = await localUserRecipeAnnotationUpdatedAt(uaVariantId: uaVariantId) ?? 0
                if cloudUpdatedAt <= localUpdatedAt { continue }

                let doseText = (data["dose_text"] as? String)
                let quantityN = (data["quantity_n"] as? String)
                let formRaw = (data["form_raw"] as? String)
                let signaText = (data["signa_text"] as? String)

                await applyCloudUserRecipeAnnotation(
                    uaVariantId: uaVariantId,
                    doseText: doseText,
                    quantityN: quantityN,
                    formRaw: formRaw,
                    signaText: signaText,
                    updatedAt: cloudUpdatedAt
                )

                await MainActor.run {
                    self.markVariantAnnotatedInIndex(uaVariantId: uaVariantId)
                }
            }
        } catch {
            print("[PharmaRepository] syncUserRecipeAnnotationsFromCloud failed: \(error)")
        }
    }

    private func markVariantAnnotatedInIndex(uaVariantId: String) {
        guard let idx = self.index else { return }
        self.index = idx.map { item in
            if item.result.uaVariantId != uaVariantId { return item }
            if item.result.isAnnotated { return item }
            let updated = DrugSearchResult(
                uaVariantId: item.result.uaVariantId,
                brandName: item.result.brandName,
                innName: item.result.innName,
                composition: item.result.composition,
                manufacturer: item.result.manufacturer,
                source: item.result.source,
                formDoseLine: item.result.formDoseLine,
                rxStatus: item.result.rxStatus,
                isAnnotated: true,
                registry: item.result.registry,
                dosageFormText: item.result.dosageFormText,
                dispensingConditions: item.result.dispensingConditions
            )
            return (updated, item.searchText)
        }
    }

    private func localUserRecipeAnnotationUpdatedAt(uaVariantId: String) async -> Int64? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let row = try? self.sqlite.querySingleRow(
                    sql: """
                    SELECT updated_at
                    FROM user_recipe_annotations
                    WHERE ua_variant_id = ?
                    LIMIT 1
                    """,
                    binds: [.text(uaVariantId)]
                ) {
                    if let s = row["updated_at"] ?? nil, let v = Int64(s) {
                        continuation.resume(returning: v)
                        return
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func applyCloudUserRecipeAnnotation(
        uaVariantId: String,
        doseText: String?,
        quantityN: String?,
        formRaw: String?,
        signaText: String?,
        updatedAt: Int64
    ) async {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try self.sqlite.execute(
                        sql: """
                        INSERT INTO user_recipe_annotations (ua_variant_id, dose_text, quantity_n, form_raw, signa_text, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(ua_variant_id) DO UPDATE SET
                            dose_text = excluded.dose_text,
                            quantity_n = excluded.quantity_n,
                            form_raw = excluded.form_raw,
                            signa_text = excluded.signa_text,
                            updated_at = excluded.updated_at;
                        """,
                        binds: [
                            .text(uaVariantId),
                            doseText != nil ? .text(doseText!) : .null,
                            quantityN != nil ? .text(quantityN!) : .null,
                            formRaw != nil ? .text(formRaw!) : .null,
                            signaText != nil ? .text(signaText!) : .null,
                            .int(updatedAt)
                        ]
                    )
                } catch {
                }
                continuation.resume(returning: ())
            }
        }
    }
#endif
}

#if !(canImport(FirebaseAuth) && canImport(FirebaseFirestore))
extension PharmaRepository {
    func listSharedRecipesFromCloud(searchQuery: String? = nil, limit: Int = 200) async throws -> [WikiRecipeItem] {
        _ = searchQuery
        _ = limit
        throw NSError(
            domain: "PharmaRepository",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Wiki: Firebase Firestore is not available in this build (canImport(FirebaseFirestore) == false)."]
        )
    }

    func pushLocalSharedRecipesToCloud() async {
    }
}
#endif
