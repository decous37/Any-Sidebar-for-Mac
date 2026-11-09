import Foundation
public struct EncodedRequest: Sendable { public let body: Data; public let budget: BudgetReport }
public enum BudgetValidator {
    public static func encode(messages: [FrozenMessage], submission: FrozenSubmission, options: ResolvedOptions, model: ModelCapabilities, assets: [ID:ImageAsset], store: any AttachmentStore) throws -> EncodedRequest {
        var imageCount=0, textBytes=0, violations: [String] = []
        var wire: [[String:Any]] = []
        for message in messages {
            guard ["system","assistant","user"].contains(message.role) else { throw AppFault("INVALID_ARGUMENT","消息角色无效。") }
            var content: [[String:Any]]=[]
            for part in message.parts {
                if part.type == "text", let text=part.text { textBytes += text.utf8.count; content.append(["type":"text","text":text]) }
                else if part.type == "image", message.role == "user", let id=part.imageId, let asset=assets[id], asset.sha256 == part.sha256 {
                    imageCount += 1
                    if asset.byteLength > 10*1024*1024 { violations.append("IMAGE_TOO_LARGE") }
                    guard let rules=model.imageRules, model.inputModalities.contains("image") else { throw AppFault("MODEL_IMAGE_UNSUPPORTED","当前模型不支持图片，请选择 Flash 或移除图片。") }
                    if asset.byteLength > rules.maxInlineBytes { violations.append("IMAGE_TOO_LARGE") }
                    let data=try store.read(asset)
                    guard data.count == asset.byteLength else { throw AppFault("IMAGE_MISSING","截图已损坏，无法发送。") }
                    content.append(["type":"image_url","image_url":["url":"data:image/png;base64,"+data.base64EncodedString(),"detail":"original"]])
                } else { throw AppFault("IMAGE_MISSING","消息或截图不可用。") }
            }
            if message.role == "user" { wire.append(["role":"user","content":content]) }
            else { wire.append(["role":message.role,"content":message.parts.compactMap(\.text).joined()]) }
        }
        if submission.images.count > 9 || imageCount > 16 { violations.append("IMAGE_COUNT_EXCEEDED") }
        if let rules=model.imageRules {
            let maxDimension=imageCount >= rules.manyImagesThreshold ? rules.manyImagesMaxDimension : rules.maxDimension
            for part in messages.flatMap(\.parts).filter({$0.type == "image"}) {
                if let id=part.imageId, let asset=assets[id], max(asset.width,asset.height) > maxDimension { violations.append("IMAGE_DIMENSION_EXCEEDED") }
            }
        }
        var request: [String:Any] = ["model":options.modelId,"messages":wire,"thinking":["type":options.thinkingEnabled ? "enabled" : "disabled"],"max_tokens":options.maxOutputTokens,"stream":true]
        if let effort=options.reasoningEffort { request["reasoning_effort"]=effort }
        let body=try JSONSerialization.data(withJSONObject:request,options:[.sortedKeys,.withoutEscapingSlashes])
        if body.count > min(24*1024*1024,model.imageRules?.maxBodyBytes ?? Int.max) { violations.append("REQUEST_BODY_TOO_LARGE") }
        let imageTokens=imageCount*(model.imageRules?.maxTokensPerImage ?? 1024), envelope=4096+256*messages.count
        if textBytes+imageTokens+envelope+options.maxOutputTokens > model.contextTokens { violations.append("CONTEXT_TOO_LARGE") }
        let budget=BudgetReport(newImageCount:submission.images.count,requestImageParts:imageCount,encodedBodyBytes:body.count,textTokenUpperBound:textBytes,imageTokenUpperBound:imageTokens,reservedEnvelopeTokens:envelope,reservedOutputTokens:options.maxOutputTokens,modelContextTokens:model.contextTokens,allowed:violations.isEmpty,violations:Array(Set(violations)).sorted())
        guard budget.allowed else { throw AppFault(budget.violations[0],"资料超出请求限制（\(budget.violations.joined(separator:"、"))），请减少资料或新建任务。") }
        return EncodedRequest(body:body,budget:budget)
    }
}
