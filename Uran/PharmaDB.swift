import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Models

public enum MateriaRole: String {
    case basis        // основное
    case adjuvans     // содействующее
    case corrigens    // корригирующее
    case menstruum    // основа/растворитель/наполнитель (constituens/menstruum)
}

public struct PharmaPrescription {
    public let id: String

    // Inscriptio / Datum / Nomen aegroti / Nomen medici
    public var inscriptio: String?
    public var datumISO: String?          // YYYY-MM-DD
    public var patientName: String?
    public var patientAge: String?
    public var doctorName: String?

    // Invocatio / Subscriptio / Signatura
    public var invocatio: String?         // обычно "Rp.:"
    public var subscriptio: String?       // "Misce. Da." / "M.f." / ...
    public var signatura: String?         // "Signa: ..."

    // подписи/печати
    public var doctorSignatureText: String?
    public var stampsText: String?        // любые печати/отметки

    public init(
        id: String = UUID().uuidString,
        inscriptio: String? = nil,
        datumISO: String? = nil,
        patientName: String? = nil,
        patientAge: String? = nil,
        doctorName: String? = nil,
        invocatio: String? = "Rp.:",
        subscriptio: String? = nil,
        signatura: String? = nil,
        doctorSignatureText: String? = nil,
        stampsText: String? = nil
    ) {
        self.id = id
        self.inscriptio = inscriptio
        self.datumISO = datumISO
        self.patientName = patientName
        self.patientAge = patientAge
        self.doctorName = doctorName
        self.invocatio = invocatio
        self.subscriptio = subscriptio
        self.signatura = signatura
        self.doctorSignatureText = doctorSignatureText
        self.stampsText = stampsText
    }
}

public struct PharmaPrescriptionItem {
    public let id: String
    public let prescriptionId: String

    public var orderNo: Int
    public var role: MateriaRole

    public var substanceText: String      // "Codeini phosphatis"
    public var amountValue: String?       // "0.06" / "10" / "q.s."
    public var amountUnit: String?        // "g" / "ml" / "№" / nil

    public init(
        id: String = UUID().uuidString,
        prescriptionId: String,
        orderNo: Int,
        role: MateriaRole,
        substanceText: String,
        amountValue: String? = nil,
        amountUnit: String? = nil
    ) {
        self.id = id
        self.prescriptionId = prescriptionId
        self.orderNo = orderNo
        self.role = role
        self.substanceText = substanceText
        self.amountValue = amountValue
        self.amountUnit = amountUnit
    }
}

// MARK: - DB

public final class PharmaDB {
    public static let shared = PharmaDB()

    private var db: OpaquePointer?

    private init() {}

    // 1) Открыть/создать БД
    public func open(databaseName: String = "pharma_tech.sqlite") throws {
        if db != nil { return }

        let url = try Self.dbURL(databaseName: databaseName)
        var ptr: OpaquePointer?

        if sqlite3_open(url.path, &ptr) != SQLITE_OK {
            let msg = ptr != nil ? String(cString: sqlite3_errmsg(ptr)) : "sqlite3_open failed"
            if let ptr { sqlite3_close(ptr) }
            throw DBError.openFailed(msg)
        }

        db = ptr
        try exec("PRAGMA foreign_keys = ON;")
        try migrate() // создаём таблицы
    }

    public func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    // 2) Миграция (таблицы)
    private func migrate() throws {
        // recipes header + tail
        try exec("""
        CREATE TABLE IF NOT EXISTS prescriptions (
          id TEXT PRIMARY KEY,

          inscriptio TEXT,
          datum_iso TEXT,
          patient_name TEXT,
          patient_age TEXT,
          doctor_name TEXT,

          invocatio TEXT,
          subscriptio TEXT,
          signatura TEXT,

          doctor_signature_text TEXT,
          stamps_text TEXT,

          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT
        );
        """)

        // designatio materiarum rows
        try exec("""
        CREATE TABLE IF NOT EXISTS prescription_items (
          id TEXT PRIMARY KEY,
          prescription_id TEXT NOT NULL,

          order_no INTEGER NOT NULL,
          role TEXT NOT NULL,                 -- basis/adjuvans/corrigens/menstruum

          substance_text TEXT NOT NULL,
          amount_value TEXT,
          amount_unit TEXT,

          FOREIGN KEY(prescription_id) REFERENCES prescriptions(id) ON DELETE CASCADE
        );
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_items_rx ON prescription_items(prescription_id);")
        try exec("CREATE INDEX IF NOT EXISTS idx_items_order ON prescription_items(prescription_id, order_no);")
    }

    // MARK: - CRUD (минимум)

    public func createPrescription(_ rx: PharmaPrescription, items: [PharmaPrescriptionItem]) throws {
        try requireOpen()

        try exec("BEGIN;")
        do {
            try exec("""
            INSERT INTO prescriptions (
              id, inscriptio, datum_iso, patient_name, patient_age, doctor_name,
              invocatio, subscriptio, signatura, doctor_signature_text, stamps_text, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,datetime('now'));
            """, bind: [
                rx.id,
                rx.inscriptio,
                rx.datumISO,
                rx.patientName,
                rx.patientAge,
                rx.doctorName,
                rx.invocatio,
                rx.subscriptio,
                rx.signatura,
                rx.doctorSignatureText,
                rx.stampsText
            ])

            for it in items {
                try exec("""
                INSERT INTO prescription_items (
                  id, prescription_id, order_no, role, substance_text, amount_value, amount_unit
                ) VALUES (?,?,?,?,?,?,?);
                """, bind: [
                    it.id,
                    it.prescriptionId,
                    it.orderNo,
                    it.role.rawValue,
                    it.substanceText,
                    it.amountValue,
                    it.amountUnit
                ])
            }

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func updatePrescription(_ rx: PharmaPrescription) throws {
        try requireOpen()

        try exec("""
        UPDATE prescriptions
        SET inscriptio = ?,
            datum_iso = ?,
            patient_name = ?,
            patient_age = ?,
            doctor_name = ?,
            invocatio = ?,
            subscriptio = ?,
            signatura = ?,
            doctor_signature_text = ?,
            stamps_text = ?,
            updated_at = datetime('now')
        WHERE id = ?;
        """, bind: [
            rx.inscriptio,
            rx.datumISO,
            rx.patientName,
            rx.patientAge,
            rx.doctorName,
            rx.invocatio,
            rx.subscriptio,
            rx.signatura,
            rx.doctorSignatureText,
            rx.stampsText,
            rx.id
        ])

        let ch = try query("SELECT changes() AS n;")
        let n = ch.first?.int("n") ?? 0
        if n == 0 { throw DBError.notFound }
    }

    public func fetchPrescription(id: String) throws -> (PharmaPrescription, [PharmaPrescriptionItem]) {
        try requireOpen()

        // header
        let rows = try query("""
        SELECT id, inscriptio, datum_iso, patient_name, patient_age, doctor_name,
               invocatio, subscriptio, signatura, doctor_signature_text, stamps_text
        FROM prescriptions WHERE id = ? LIMIT 1;
        """, bind: [id])

        guard let r = rows.first else { throw DBError.notFound }

        let rx = PharmaPrescription(
            id: r.str("id") ?? id,
            inscriptio: r.str("inscriptio"),
            datumISO: r.str("datum_iso"),
            patientName: r.str("patient_name"),
            patientAge: r.str("patient_age"),
            doctorName: r.str("doctor_name"),
            invocatio: r.str("invocatio"),
            subscriptio: r.str("subscriptio"),
            signatura: r.str("signatura"),
            doctorSignatureText: r.str("doctor_signature_text"),
            stampsText: r.str("stamps_text")
        )

        // items
        let itemsRows = try query("""
        SELECT id, prescription_id, order_no, role, substance_text, amount_value, amount_unit
        FROM prescription_items
        WHERE prescription_id = ?
        ORDER BY order_no ASC;
        """, bind: [id])

        let items: [PharmaPrescriptionItem] = itemsRows.compactMap { row in
            guard
                let itId = row.str("id"),
                let rxId = row.str("prescription_id"),
                let roleStr = row.str("role"),
                let role = MateriaRole(rawValue: roleStr),
                let subst = row.str("substance_text")
            else { return nil }

            return PharmaPrescriptionItem(
                id: itId,
                prescriptionId: rxId,
                orderNo: row.int("order_no") ?? 0,
                role: role,
                substanceText: subst,
                amountValue: row.str("amount_value"),
                amountUnit: row.str("amount_unit")
            )
        }

        return (rx, items)
    }

    public func listPrescriptions(limit: Int = 200) throws -> [PharmaPrescription] {
        try requireOpen()

        let rows = try query("""
        SELECT id, inscriptio, datum_iso, patient_name, patient_age, doctor_name,
               invocatio, subscriptio, signatura, doctor_signature_text, stamps_text
        FROM prescriptions
        ORDER BY COALESCE(updated_at, created_at) DESC
        LIMIT ?;
        """, bind: [limit])

        return rows.map { r in
            PharmaPrescription(
                id: r.str("id") ?? UUID().uuidString,
                inscriptio: r.str("inscriptio"),
                datumISO: r.str("datum_iso"),
                patientName: r.str("patient_name"),
                patientAge: r.str("patient_age"),
                doctorName: r.str("doctor_name"),
                invocatio: r.str("invocatio"),
                subscriptio: r.str("subscriptio"),
                signatura: r.str("signatura"),
                doctorSignatureText: r.str("doctor_signature_text"),
                stampsText: r.str("stamps_text")
            )
        }
    }

    // MARK: - Helpers

    private func requireOpen() throws {
        if db == nil { throw DBError.notOpen }
    }

    private func exec(_ sql: String, bind: [Any?] = []) throws {
        try requireOpen()

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError.sqlPrepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindValues(bind, to: stmt)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DBError.sqlStep(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query(_ sql: String, bind: [Any?] = []) throws -> [[String: Any?]] {
        try requireOpen()

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError.sqlPrepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindValues(bind, to: stmt)

        var result: [[String: Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let colCount = sqlite3_column_count(stmt)
            var row: [String: Any?] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL:
                    row[name] = nil
                default:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                }
            }
            result.append(row)
        }
        return result
    }

    private func bindValues(_ bind: [Any?], to stmt: OpaquePointer?) throws {
        for (idx, val) in bind.enumerated() {
            let i = Int32(idx + 1)

            if val == nil {
                sqlite3_bind_null(stmt, i)
                continue
            }

            switch val {
            case let v as String:
                sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case let v as Int:
                sqlite3_bind_int64(stmt, i, sqlite3_int64(v))
            case let v as Double:
                sqlite3_bind_double(stmt, i, v)
            case let v as Bool:
                sqlite3_bind_int(stmt, i, v ? 1 : 0)
            default:
                // безопасный fallback — строка
                let s = String(describing: val!)
                sqlite3_bind_text(stmt, i, s, -1, SQLITE_TRANSIENT)
            }
        }
    }

    private static func dbURL(databaseName: String) throws -> URL {
#if os(iOS) || os(tvOS) || os(watchOS)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
#else
        // macOS: Application Support
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
#endif
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent(databaseName)
    }

    // MARK: - Errors
    public enum DBError: Error {
        case notOpen
        case openFailed(String)
        case sqlPrepare(String)
        case sqlStep(String)
        case notFound
    }
}

// удобные геттеры
private extension Dictionary where Key == String, Value == Any? {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int? { self[k] as? Int }
}
