import Foundation
import Testing
@testable import ReadingCore
@Suite struct BudgetIntegrationTests {
    func cat() throws -> ModelCatalog{try ModelCatalog(data:Data(contentsOf:URL(fileURLWithPath:ProcessInfo.processInfo.environment["ANY_SIDEBAR_CONTRACTS"]!).appendingPathComponent("model-capabilities.json")))}
    func input(count:Int,newCount:Int,width:Int=200,bytes:Int=3) throws -> ([FrozenMessage],FrozenSubmission,[ID:ImageAsset],MemoryAssets) {
        let id=newID(),source=SourceInfo(kind:"screen-region"),asset=ImageAsset(id:id,source:source,width:width,height:200,byteLength:bytes,sha256:"hash",storageKey:"images/a.png",thumbnailKey:nil),image=FrozenImage(draftItemId:newID(),itemRevision:0,imageId:id,sha256:"hash")
        var draft=ReadingDraft(taskId:newID());draft.images=(0..<newCount).map{_ in DraftImage(imageId:id)}
        return ([FrozenMessage(role:"user",parts:(0..<count).map{_ in .image(image)})],try FrozenSubmission(draft:draft,assets:[id:asset]),[id:asset],MemoryAssets(bytes:Data(repeating:1,count:bytes)))
    }
    @Test func nineNewAndSixteenTotal() throws {
        let cat=try cat(),model=try cat.model("deepseek-flash"),options=try cat.resolve(PreferencesRecord())
        let(a,b,c,d)=try input(count:16,newCount:9)
        let encoded=try BudgetValidator.encode(messages:a,submission:b,options:options,model:model,assets:c,store:d)
        #expect(encoded.budget.requestImageParts==16);#expect(encoded.budget.imageTokenUpperBound==16384)
        let(e,f,g,h)=try input(count:17,newCount:9)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:e,submission:f,options:options,model:model,assets:g,store:h)}
        let(i,j,k,l)=try input(count:10,newCount:10)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:i,submission:j,options:options,model:model,assets:k,store:l)}
    }
    @Test func manyImagesDimensionAndTextOnlyModel() throws {
        let cat=try cat(),options=try cat.resolve(PreferencesRecord()),(a,b,c,d)=try input(count:15,newCount:1,width:4097)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:a,submission:b,options:options,model:cat.model("deepseek-flash"),assets:c,store:d)}
        let(e,f,g,h)=try input(count:1,newCount:1)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:e,submission:f,options:options,model:cat.model("deepseek-v4-pro"),assets:g,store:h)}
    }
    @Test func actualBase64BodyLimitAndContextRefusal() throws {
        let cat=try cat(),options=try cat.resolve(PreferencesRecord()),(a,b,c,d)=try input(count:3,newCount:3,bytes:7*1024*1024)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:a,submission:b,options:options,model:cat.model("deepseek-flash"),assets:c,store:d)}
        let(_,sub,_,store)=try input(count:0,newCount:0)
        #expect(throws:AppFault.self){try BudgetValidator.encode(messages:[.text("user",String(repeating:"a",count:1048576))],submission:sub,options:options,model:cat.model("deepseek-flash"),assets:[:],store:store)}
    }
}
