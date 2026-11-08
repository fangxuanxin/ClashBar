import Foundation
import SQLite3

final class HistoryStore {
    enum StoreError: Error, LocalizedError {
        case database(String)
        var errorDescription: String? {
            switch self { case .database(let message): return message }
        }
    }

    static let retention: TimeInterval = 30 * 86400
    private var database: OpaquePointer?
    private let url: URL
    private var backupDay: String?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open history"
            if let database { sqlite3_close(database) }
            database = nil
            throw StoreError.database(message)
        }
        do {
            sqlite3_busy_timeout(database, 3000)
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA secure_delete = ON")
            let version = try query("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first ?? 0
            guard version <= 2 else { throw StoreError.database("History schema is newer than this app") }
            if version == 0 {
                try transaction {
                    try execute("CREATE TABLE intervals (id TEXT PRIMARY KEY, controller TEXT NOT NULL, label TEXT NOT NULL, start REAL NOT NULL, end REAL NOT NULL, session TEXT NOT NULL, state TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL)")
                    try execute("CREATE INDEX intervals_controller_time ON intervals(controller, start)")
                    try execute("CREATE TABLE samples (controller TEXT NOT NULL, time REAL NOT NULL, node TEXT NOT NULL, delay INTEGER)")
                    try execute("CREATE INDEX samples_controller_time ON samples(controller, time)")
                    try execute("PRAGMA user_version = 1")
                }
            }
            if version < 2 {
                if version == 1 { try backup(at: Date()) }
                try transaction {
                    try execute("ALTER TABLE samples ADD COLUMN origin TEXT NOT NULL DEFAULT 'clashbar'")
                    try execute("ALTER TABLE samples ADD COLUMN test_url TEXT NOT NULL DEFAULT ''")
                    try execute("CREATE UNIQUE INDEX samples_core_identity ON samples(controller,node,time,test_url) WHERE origin = 'core'")
                    try execute("PRAGMA user_version = 2")
                }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK || result == SQLITE_DONE || result == SQLITE_ROW else {
            throw StoreError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func statement(_ sql: String, values: [Any?]) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &prepared, nil))
        guard let prepared else { throw StoreError.database("Empty history statement") }
        do {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                if let value = value as? String {
                    try check(sqlite3_bind_text(prepared, index, value, -1, transient))
                } else if let value = value as? Double {
                    try check(sqlite3_bind_double(prepared, index, value))
                } else if let value = value as? Int {
                    try check(sqlite3_bind_int64(prepared, index, Int64(value)))
                } else {
                    try check(sqlite3_bind_null(prepared, index))
                }
            }
        } catch { sqlite3_finalize(prepared); throw error }
        return prepared
    }

    private func execute(_ sql: String, _ values: [Any?] = []) throws {
        let prepared = try statement(sql, values: values)
        defer { sqlite3_finalize(prepared) }
        try check(sqlite3_step(prepared))
    }

    private func query<Value>(_ sql: String, _ values: [Any?] = [], map: (OpaquePointer) throws -> Value) throws -> [Value] {
        let prepared = try statement(sql, values: values)
        defer { sqlite3_finalize(prepared) }
        var results: [Value] = []
        while true {
            let result = sqlite3_step(prepared)
            if result == SQLITE_DONE { return results }
            try check(result)
            results.append(try map(prepared))
        }
    }

    private func string(_ prepared: OpaquePointer, _ column: Int32) -> String {
        String(cString: sqlite3_column_text(prepared, column))
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func decodeInterval(_ prepared: OpaquePointer) throws -> HistoryInterval {
        HistoryInterval(id: string(prepared, 0), start: Date(timeIntervalSince1970: sqlite3_column_double(prepared, 1)),
                        end: Date(timeIntervalSince1970: sqlite3_column_double(prepared, 2)), session: string(prepared, 3),
                        state: try JSONDecoder().decode(HistoryState.self, from: Data(string(prepared, 4).utf8)),
                        kind: string(prepared, 5), source: string(prepared, 6))
    }

    func observe(controller: String, label: String, state: HistoryState, session: String,
                 at time: Date, maximumGap: TimeInterval, source: String = "observed") throws {
        try maintain(at: time)
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try transaction {
            let previous = try query("SELECT id,start,end,session,state,kind,source FROM intervals WHERE controller = ? ORDER BY start DESC, rowid DESC LIMIT 1", [controller], map: decodeInterval).first
            let continuous = previous.map { $0.session == session && time >= $0.end && time.timeIntervalSince($0.end) <= maximumGap } ?? false
            if let previous, continuous {
                try execute("UPDATE intervals SET end = ?, label = ? WHERE id = ?", [time.timeIntervalSince1970, label, previous.id])
                if previous.state == state { return }
            }
            let kind: String
            if let previous, continuous {
                if previous.state.mode != state.mode { kind = "mode" }
                else if !previous.state.topologyMatches(state) { kind = "configuration" }
                else { kind = "change" }
            } else { kind = "baseline" }
            try execute("INSERT INTO intervals VALUES (?,?,?,?,?,?,?,?,?)",
                        [UUID().uuidString, controller, label, time.timeIntervalSince1970, time.timeIntervalSince1970, session, encoded, kind, source])
        }
    }

    func sample(controller: String, node: String, delay: Int?, at time: Date, origin: String = "clashbar", testURL: String = "") throws {
        try execute("INSERT OR IGNORE INTO samples(controller,time,node,delay,origin,test_url) VALUES (?,?,?,?,?,?)",
                    [controller, time.timeIntervalSince1970, node, delay, origin, testURL])
    }

    func report(controller: String?, from start: Date, to end: Date) throws -> HistoryReport {
        var report = HistoryReport()
        report.controllers = try query("SELECT controller, label FROM intervals WHERE end >= ? GROUP BY controller ORDER BY MAX(end) DESC", [end.addingTimeInterval(-Self.retention).timeIntervalSince1970]) {
            HistoryControllerInfo(id: self.string($0, 0), name: self.string($0, 1))
        }
        guard let controller else { return report }
        report.intervals = try query("SELECT id,start,end,session,state,kind,source FROM intervals WHERE controller = ? AND end >= ? AND start <= ? ORDER BY start, rowid", [controller, start.timeIntervalSince1970, end.timeIntervalSince1970], map: decodeInterval)
        report.samples = try query("SELECT time,node,delay,origin,test_url FROM samples WHERE controller = ? AND time >= ? AND time <= ? ORDER BY time", [controller, start.timeIntervalSince1970, end.timeIntervalSince1970]) {
            HistorySample(time: Date(timeIntervalSince1970: sqlite3_column_double($0, 0)), node: self.string($0, 1),
                          delay: sqlite3_column_type($0, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int($0, 2)),
                          origin: self.string($0, 3), testURL: self.string($0, 4))
        }
        return report
    }

    func maintain(at time: Date) throws {
        let day = String(Int(time.timeIntervalSince1970 / 86400))
        guard backupDay != day else { return }
        let cutoff = time.addingTimeInterval(-Self.retention).timeIntervalSince1970
        try backup(at: time)
        try transaction {
            try execute("DELETE FROM intervals WHERE end < ?", [cutoff])
            try execute("UPDATE intervals SET start = ? WHERE start < ?", [cutoff, cutoff])
            try execute("DELETE FROM samples WHERE time < ?", [cutoff])
        }
        backupDay = day
    }

    func backup(at time: Date) throws {
        let directory = url.deletingLastPathComponent().appendingPathComponent("database_backup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent("history-\(Int(time.timeIntervalSince1970))-\(UUID().uuidString).sqlite")
        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK else {
            sqlite3_close(target)
            throw StoreError.database("Cannot open history backup")
        }
        defer { sqlite3_close(target) }
        guard let copy = sqlite3_backup_init(target, "main", database, "main") else {
            throw StoreError.database("Cannot create history backup")
        }
        let result = sqlite3_backup_step(copy, -1)
        let finished = sqlite3_backup_finish(copy)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw StoreError.database("Cannot finish history backup") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "sqlite" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(5) { try FileManager.default.removeItem(at: old) }
    }

    func clear() throws {
        try backup(at: Date())
        try transaction {
            try execute("DELETE FROM intervals")
            try execute("DELETE FROM samples")
        }
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let directory = url.deletingLastPathComponent().appendingPathComponent("database_backup", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        backupDay = nil
    }
}

actor HistoryService {
    private let store: HistoryStore

    init(url: URL) throws { store = try HistoryStore(url: url) }

    func observe(controller: String, label: String, state: HistoryState, session: String, at time: Date,
                 maximumGap: TimeInterval, source: String) throws {
        try Task.checkCancellation()
        try store.observe(controller: controller, label: label, state: state, session: session, at: time,
                          maximumGap: maximumGap, source: source)
    }

    func sample(controller: String, node: String, delay: Int?, at time: Date, origin: String, testURL: String) throws {
        try Task.checkCancellation()
        try store.sample(controller: controller, node: node, delay: delay, at: time, origin: origin, testURL: testURL)
    }

    func report(controller: String?, from start: Date, to end: Date) throws -> HistoryReport {
        try store.maintain(at: end)
        return try store.report(controller: controller, from: start, to: end)
    }

    func clear() throws { try store.clear() }
}
