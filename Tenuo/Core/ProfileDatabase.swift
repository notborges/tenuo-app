import Foundation
import SQLite3

final class ProfileDatabase {
    private var connection: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard
            sqlite3_open_v2(
                url.path, &connection,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK
        else {
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw ProfileSyncError.storageUnavailable
        }
        do {
            sqlite3_busy_timeout(connection, 3_000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute(
                "CREATE TABLE IF NOT EXISTS profile_state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)"
            )
        } catch {
            sqlite3_close(connection)
            connection = nil
            throw error
        }
    }

    func load() throws -> ProfileSyncState? {
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                connection, "SELECT payload FROM profile_state WHERE id=1", -1, &statement, nil)
                == SQLITE_OK
        else {
            throw ProfileSyncError.storageUnavailable
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw ProfileSyncError.storageUnavailable
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let state = try JSONDecoder().decode(ProfileSyncState.self, from: data)
        try state.validate()
        return state
    }

    func save(_ state: ProfileSyncState) throws {
        try state.validate()
        let data = try ProfileDocument.encoder.encode(state)
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard
                sqlite3_prepare_v2(
                    connection, "INSERT OR REPLACE INTO profile_state (id,payload) VALUES (1,?)",
                    -1, &statement, nil) == SQLITE_OK
            else {
                throw ProfileSyncError.storageUnavailable
            }
            defer { sqlite3_finalize(statement) }
            let result = data.withUnsafeBytes { bytes -> Int32 in
                guard
                    sqlite3_bind_blob(
                        statement, 1, bytes.baseAddress, Int32(bytes.count),
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK
                else { return SQLITE_ERROR }
                return sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw ProfileSyncError.storageUnavailable }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw ProfileSyncError.storageUnavailable
        }
    }

    deinit { if let connection { sqlite3_close(connection) } }
}
