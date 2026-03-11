import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteServiceError: Error, LocalizedError {
    case openDatabaseFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openDatabaseFailed(let message): return message
        case .prepareFailed(let message): return message
        case .stepFailed(let message): return message
        case .bindFailed(let message): return message
        }
    }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
    case int(Int64)
    case null
}

final class SQLiteService {
    private var db: OpaquePointer?

    init(readOnlyDatabaseAtPath path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw SQLiteServiceError.openDatabaseFailed(message)
        }

        _ = sqlite3_exec(handle, "PRAGMA journal_mode=DELETE;", nil, nil, nil)

        self.db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func querySingleRow(sql: String, binds: [SQLiteValue]) throws -> [String: String?]? {
        let rows = try queryRows(sql: sql, binds: binds, limit: 1)
        return rows.first
    }

    func queryRows(sql: String, binds: [SQLiteValue], limit: Int? = nil) throws -> [[String: String?]] {
        guard let db else { return [] }
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteServiceError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in binds.enumerated() {
            let idx = Int32(index + 1)
            let rc: Int32
            switch value {
            case .text(let string):
                rc = sqlite3_bind_text(statement, idx, string, -1, SQLITE_TRANSIENT)
            case .double(let number):
                rc = sqlite3_bind_double(statement, idx, number)
            case .int(let number):
                rc = sqlite3_bind_int64(statement, idx, number)
            case .null:
                rc = sqlite3_bind_null(statement, idx)
            }
            if rc != SQLITE_OK {
                throw SQLiteServiceError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        var results: [[String: String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let columnCount = sqlite3_column_count(statement)
                var row: [String: String?] = [:]
                row.reserveCapacity(Int(columnCount))
                for col in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(statement, col))
                    if sqlite3_column_type(statement, col) == SQLITE_NULL {
                        row[name] = nil
                    } else if let cString = sqlite3_column_text(statement, col) {
                        row[name] = String(cString: cString)
                    } else {
                        row[name] = nil
                    }
                }
                results.append(row)
                if let limit, results.count >= limit { break }
            } else if step == SQLITE_DONE {
                break
            } else {
                throw SQLiteServiceError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        return results
    }

    func execute(sql: String, binds: [SQLiteValue] = []) throws {
        guard let db else { return }
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteServiceError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in binds.enumerated() {
            let idx = Int32(index + 1)
            let rc: Int32
            switch value {
            case .text(let string):
                rc = sqlite3_bind_text(statement, idx, string, -1, SQLITE_TRANSIENT)
            case .double(let number):
                rc = sqlite3_bind_double(statement, idx, number)
            case .int(let number):
                rc = sqlite3_bind_int64(statement, idx, number)
            case .null:
                rc = sqlite3_bind_null(statement, idx)
            }
            if rc != SQLITE_OK {
                throw SQLiteServiceError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        let step = sqlite3_step(statement)
        if step != SQLITE_DONE {
            throw SQLiteServiceError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}
