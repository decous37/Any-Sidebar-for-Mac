import Foundation
import Testing
import ReadingCore
@testable import ReadingStorage
@Suite struct RepositoryTests {
    @Test func durabilityBackupAndRollback() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:directory)}
        let db=try SQLiteDatabase(directory:directory)
        var state=PersistedState();let task=ReadingTaskRecord(title:"阅读任务");state.tasks[task.id]=task;state.drafts[task.id]=ReadingDraft(taskId:task.id)
        try db.save(state);#expect(try db.load() == state)
        var invalid=state;let bad=ReadingDraft(taskId:newID());invalid.drafts[bad.taskId]=bad
        #expect(throws:AppFault.self){try db.save(invalid)}
        #expect(try db.load() == state)
        try db.backup(to:directory.appendingPathComponent("backup.sqlite3"))
        #expect(FileManager.default.fileExists(atPath:directory.appendingPathComponent("backup.sqlite3").path))
    }
    @Test func actualPNGIntegrityAndReferenceCollection() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:directory)}
        let store=try FileAttachmentStore(root:directory)
        let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9N8AAAAASUVORK5CYII=")!
        let asset=try store.persist(png:png,source:SourceInfo(kind:"screen-region"))
        #expect(try store.read(asset)==png)
        try store.removeUnreferenced(keeping:[asset.id]);#expect(try store.read(asset)==png)
        try store.removeUnreferenced(keeping:[])
        #expect(throws:AppFault.self){try store.read(asset)}
    }
    @Test func traversalRejected() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:directory)}
        let store=try FileAttachmentStore(root:directory)
        let asset=ImageAsset(id:newID(),source:SourceInfo(kind:"screen-region"),width:1,height:1,byteLength:0,sha256:"",storageKey:"../secret",thumbnailKey:nil)
        #expect(throws:AppFault.self){try store.read(asset)}
    }
}
