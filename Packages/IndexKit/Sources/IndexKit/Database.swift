import Foundation
import SQLite3

/// A minimal wrapper over SQLite's C API, used only inside `SearchIndex`.
final class Database {
    enum DatabaseError: Error, CustomStringConvertible {
        case sqlite(String)
        var description: String {
            switch self { case .sqlite(let message): "SQLite: \(message)" }
        }
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens (creating if needed) a database file, or an in-memory one when `url` is nil.
    init(url: URL?) throws {
        let path = url?.path ?? ":memory:"
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            defer { sqlite3_close(handle) }
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DatabaseError.sqlite(message)
        }
    }

    /// Runs a statement for each row of bindings; returns the rows it produces.
    @discardableResult
    func query(_ sql: String, _ bindings: [Any?] = []) throws -> [[Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite("\(String(cString: sqlite3_errmsg(handle))) in \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case let number as Int: sqlite3_bind_int64(statement, position, Int64(number))
            case let number as Int64: sqlite3_bind_int64(statement, position, number)
            case let number as Double: sqlite3_bind_double(statement, position, number)
            default: sqlite3_bind_null(statement, position)
            }
        }
        var rows: [[Any?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DatabaseError.sqlite("\(String(cString: sqlite3_errmsg(handle))) in \(sql)")
            }
            var row: [Any?] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(Int(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(statement, column)))
                default: row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }

    var lastInsertedRow: Int { Int(sqlite3_last_insert_rowid(handle)) }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
