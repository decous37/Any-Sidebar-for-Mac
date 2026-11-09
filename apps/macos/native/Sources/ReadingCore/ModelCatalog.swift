import Foundation
public struct ImageRules: Codable, Sendable, Equatable {
    public var maxInlineBytes: Int; public var maxBodyBytes: Int; public var maxImageParts: Int
    public var maxDimension: Int; public var manyImagesThreshold: Int; public var manyImagesMaxDimension: Int; public var maxTokensPerImage: Int
}
public struct ModelCapabilities: Codable, Sendable, Equatable {
    public var providerId: String; public var modelId: String; public var label: String; public var inputModalities: [String]
    public var reasoningEfforts: [String]; public var contextTokens: Int; public var maxOutputTokens: Int; public var imageRules: ImageRules?
    public var version: String; public var verifiedDocumentationDate: String
}
public struct ModelCatalog: Codable, Sendable {
    public var version: String; public var models: [ModelCapabilities]
    public init(data: Data) throws { self = try JSONDecoder().decode(Self.self,from:data) }
    public func model(_ id: String) throws -> ModelCapabilities {
        guard let model=models.first(where:{$0.modelId == id}) else { throw AppFault("INVALID_ARGUMENT","未知模型，请重新选择。") }; return model
    }
    public func resolve(_ preferences: PreferencesRecord) throws -> ResolvedOptions {
        let m=try model(preferences.modelId)
        guard m.reasoningEfforts.contains(preferences.reasoningEffort) else { throw AppFault("INVALID_ARGUMENT","此模型不支持该思考强度。") }
        return ResolvedOptions(modelId:m.modelId,thinkingEnabled:preferences.thinkingEnabled,reasoningEffort:preferences.thinkingEnabled ? preferences.reasoningEffort : nil,maxOutputTokens:min(m.maxOutputTokens,!preferences.thinkingEnabled ? 8192 : preferences.reasoningEffort == "max" ? 131072 : 65536))
    }
}
