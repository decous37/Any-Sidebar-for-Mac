import Foundation
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String:JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c=try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v=try? c.decode(Bool.self) { self = .bool(v) }
        else if let v=try? c.decode(String.self) { self = .string(v) }
        else if let v=try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v=try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String:JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c=encoder.singleValueContainer()
        switch self { case .object(let v):try c.encode(v);case .array(let v):try c.encode(v);case .string(let v):try c.encode(v);case .number(let v):try c.encode(v);case .bool(let v):try c.encode(v);case .null:try c.encodeNil() }
    }
    public var object: [String:JSONValue]? { if case .object(let v)=self { return v }; return nil }
    public var string: String? { if case .string(let v)=self { return v }; return nil }
    public var int: Int? { if case .number(let v)=self,v >= 0,v <= 9007199254740991,v.rounded() == v { return Int(v) }; return nil }
    public var bool: Bool? { if case .bool(let v)=self { return v }; return nil }
    public static func encode<T:Encodable>(_ value: T) throws -> Self { try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(value)) }
    public func decode<T:Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type,from:JSONEncoder().encode(self)) }
}
public struct CommandRule: Codable, Sendable {
    public var required: [String:String]; public var optional: [String:String]
}
public struct CommandSchema: Codable, Sendable {
    public var version: Int; public var commands: [String:CommandRule]
    public init(data: Data) throws { self=try JSONDecoder().decode(Self.self,from:data) }
}
public struct BridgeRequest: Codable, Sendable {
    public var version: Int; public var viewEpoch: ID; public var messageId: ID; public var operationId: ID
    public var command: String; public var args: [String:JSONValue]
    public static func decode(_ data: Data, schema: CommandSchema, epoch: ID, allowBootstrap: Bool = false) throws -> Self {
        let raw=try JSONDecoder().decode([String:JSONValue].self,from:data)
        guard Set(raw.keys) == Set(["version","viewEpoch","messageId","operationId","command","args"]) else { throw AppFault("INVALID_ARGUMENT","消息字段无效。") }
        let request=try JSONDecoder().decode(Self.self,from:data)
        guard request.version == 1 else { throw AppFault("BRIDGE_VERSION_UNSUPPORTED","请重新打开面板。") }
        guard validID(request.messageId),validID(request.operationId),validID(request.viewEpoch),request.viewEpoch == epoch || (allowBootstrap && request.command == "bootstrap") else { throw AppFault("INVALID_ARGUMENT","面板已经过期，请重新打开。") }
        guard let rule=schema.commands[request.command], Set(rule.required.keys).isSubset(of:Set(request.args.keys)),Set(request.args.keys).isSubset(of:Set(rule.required.keys).union(rule.optional.keys)) else { throw AppFault("INVALID_ARGUMENT","操作或参数无效。") }
        for (key,value) in request.args {
            let type=rule.required[key] ?? rule.optional[key] ?? ""
            let valid: Bool
            switch type {
            case "id": valid=value.string.map(validID) ?? false
            case "string": valid=value.string != nil && (value.string?.utf8.count ?? 0) <= 2*1024*1024
            case "integer":valid=value.int != nil
            case "boolean":valid=value.bool != nil
            case "object":valid=value.object != nil
            default:valid=type.split(separator:"|").contains(Substring(value.string ?? ""))
            }
            guard valid else { throw AppFault("INVALID_ARGUMENT","操作参数类型无效。") }
        }
        return request
    }
}
public struct SendCommand: Sendable { public var taskId: ID; public var expectedDraftRevision: Int; public var expectedPreferencesRevision: Int }
public enum StopTarget: Sendable { case request(taskId: ID, requestId: ID); case operation(taskId: ID, sourceOperationId: ID) }
public struct SelectionEvent: Sendable {
    public var operationId: ID; public var taskId: ID; public var routingEpoch: Int; public var sourceLeaseId: ID; public var sourceSequence: Int
    public var outcome: Outcome
    public enum Outcome: Sendable { case selected(token: ID, source: SourceInfo, text: String); case cleared(token: ID, expectedQuoteId: ID); case unavailable(reason: String) }
    public init(operationId: ID = newID(), taskId: ID, routingEpoch: Int, sourceLeaseId: ID, sourceSequence: Int, outcome: Outcome) { self.operationId=operationId;self.taskId=taskId;self.routingEpoch=routingEpoch;self.sourceLeaseId=sourceLeaseId;self.sourceSequence=sourceSequence;self.outcome=outcome }
}
