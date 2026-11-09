import Foundation
import CSQLite
import ReadingCore
/// All access is serialized by this lock; no transaction spans an await.
public final class SQLiteDatabase: ReadingRepository, @unchecked Sendable {
    private let lock=NSLock()
    private var db: OpaquePointer?
    public let directory: URL
    public init(directory: URL) throws {
        self.directory=directory
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let path=directory.appendingPathComponent("reading.sqlite3").path
        guard sqlite3_open_v2(path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else { throw AppFault.storage }
        sqlite3_busy_timeout(db,3000)
        try execute("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        let version=try scalar("PRAGMA user_version")
        guard version <= 1 else { throw AppFault("SCHEMA_MIGRATION_FAILED","数据版本较新，请使用更新的应用。") }
        if version == 0 {
            try execute("BEGIN IMMEDIATE; CREATE TABLE metadata (key TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE tasks(id TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE assets(id TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE records(kind TEXT NOT NULL,id TEXT NOT NULL,task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,payload BLOB NOT NULL,PRIMARY KEY(kind,id)); CREATE INDEX records_task ON records(task_id,kind); CREATE TABLE asset_refs(owner_kind TEXT NOT NULL,owner_id TEXT NOT NULL,image_id TEXT NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,PRIMARY KEY(owner_kind,owner_id,image_id)); PRAGMA user_version=1; COMMIT;")
        }
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path)
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw AppFault.storage } }
    private func scalar(_ sql: String) throws -> Int { var q:OpaquePointer?;guard sqlite3_prepare_v2(db,sql,-1,&q,nil)==SQLITE_OK else{throw AppFault.storage};defer{sqlite3_finalize(q)};guard sqlite3_step(q)==SQLITE_ROW else{throw AppFault.storage};return Int(sqlite3_column_int(q,0)) }
    private func insert<T:Encodable>(_ sql: String, keys: [String], value: T) throws {
        var q:OpaquePointer?;guard sqlite3_prepare_v2(db,sql,-1,&q,nil)==SQLITE_OK else{throw AppFault.storage};defer{sqlite3_finalize(q)}
        let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        for (i,key) in keys.enumerated(){sqlite3_bind_text(q,Int32(i+1),key,-1,transient)}
        let data=try JSONEncoder().encode(value)
        _=data.withUnsafeBytes{sqlite3_bind_blob(q,Int32(keys.count+1),$0.baseAddress,Int32(data.count),transient)}
        guard sqlite3_step(q)==SQLITE_DONE else{throw AppFault.storage}
    }
    private func rows<T:Decodable>(_ sql: String, as: T.Type) throws -> [T] {
        var q:OpaquePointer?;guard sqlite3_prepare_v2(db,sql,-1,&q,nil)==SQLITE_OK else{throw AppFault.storage};defer{sqlite3_finalize(q)}
        var result:[T]=[]
        while true { let status=sqlite3_step(q);if status==SQLITE_DONE{break};guard status==SQLITE_ROW,let p=sqlite3_column_blob(q,0) else{throw AppFault.storage};let data=Data(bytes:p,count:Int(sqlite3_column_bytes(q,0)));result.append(try JSONDecoder().decode(T.self,from:data)) };return result
    }
    public func load() throws -> PersistedState {
        lock.lock();defer{lock.unlock()}
        var state=PersistedState()
        if let metadata=try rows("SELECT payload FROM metadata WHERE key='state'",as:PersistedState.self).first { state=metadata }
        return state
    }
    public func save(_ state: PersistedState) throws {
        lock.lock();defer{lock.unlock()}
        do {
            try execute("BEGIN IMMEDIATE; DELETE FROM asset_refs; DELETE FROM records; DELETE FROM tasks; DELETE FROM assets;")
            for t in state.tasks.values { try insert("INSERT INTO tasks VALUES(?,?)",keys:[t.id],value:t) }
            for a in state.assets.values { try insert("INSERT INTO assets VALUES(?,?)",keys:[a.id],value:a) }
            for d in state.drafts.values {try insert("INSERT INTO records VALUES(?,?,?,?)",keys:["draft",d.taskId,d.taskId],value:d)}
            for r in state.snapshots.values {try insert("INSERT INTO records VALUES(?,?,?,?)",keys:["snapshot",r.id,r.taskId],value:r)}
            for r in state.generations.values {try insert("INSERT INTO records VALUES(?,?,?,?)",keys:["generation",r.id,r.taskId],value:r)}
            for ref in state.references {
                var q:OpaquePointer?;guard sqlite3_prepare_v2(db,"INSERT INTO asset_refs VALUES(?,?,?)",-1,&q,nil)==SQLITE_OK else{throw AppFault.storage};defer{sqlite3_finalize(q)}
                let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
                sqlite3_bind_text(q,1,ref.ownerKind,-1,transient);sqlite3_bind_text(q,2,ref.ownerId,-1,transient);sqlite3_bind_text(q,3,ref.imageId,-1,transient)
                guard sqlite3_step(q)==SQLITE_DONE else{throw AppFault.storage}
            }
            try insert("INSERT OR REPLACE INTO metadata VALUES(?,?)",keys:["state"],value:state)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK");throw AppFault.storage }
    }
    public func backup(to url: URL) throws {
        lock.lock();defer{lock.unlock()}
        var destination:OpaquePointer?;guard sqlite3_open(url.path,&destination)==SQLITE_OK else{throw AppFault.storage};defer{sqlite3_close(destination)}
        guard let backup=sqlite3_backup_init(destination,"main",db,"main") else{throw AppFault.storage}
        let status=sqlite3_backup_step(backup,-1);let finish=sqlite3_backup_finish(backup)
        guard status==SQLITE_DONE,finish==SQLITE_OK else{throw AppFault.storage}
    }
}
