import Foundation
import ReadingCore
struct ApplicationResources: Sendable {
    let root:URL
    let catalog:ModelCatalog
    let schema:CommandSchema
    let prompt:String
    init(root:URL) throws {
        self.root=root
        catalog=try ModelCatalog(data:Data(contentsOf:root.appendingPathComponent("contracts/model-capabilities.json")))
        schema=try CommandSchema(data:Data(contentsOf:root.appendingPathComponent("contracts/bridge.schema.json")))
        prompt=try String(contentsOf:root.appendingPathComponent("contracts/desktop-reading-prompt.txt"),encoding:.utf8)
        guard FileManager.default.fileExists(atPath:root.appendingPathComponent("web/index.html").path) else{throw AppFault("RESOURCE_MISSING","应用资源不完整，请重新构建。")}
    }
}
