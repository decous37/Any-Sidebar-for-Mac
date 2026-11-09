import Foundation
import ReadingCore
public struct SSEDecoder: Sendable {
    private var lines:[String]=[]
    private var pendingLine:[UInt8]=[]
    private var skipLF=false
    public init() {}
    /// AsyncLineSequence drops blank lines, which are SSE frame boundaries. Consume raw bytes instead.
    public mutating func feed(_ byte:UInt8) throws -> [StreamDelta] {
        if skipLF {skipLF=false;if byte==10{return []}}
        if byte==10 || byte==13 {
            skipLF=byte==13
            guard let text=String(bytes:pendingLine,encoding:.utf8) else{throw AppFault("API_BAD_RESPONSE","服务返回了无效的文字编码。",retryable:true)}
            pendingLine.removeAll(keepingCapacity:true)
            return try line(text)
        }
        guard pendingLine.count<2*1024*1024 else{throw AppFault("API_BAD_RESPONSE","单条流式数据过大，请稍后重试。",retryable:true)}
        pendingLine.append(byte);return []
    }
    public mutating func finish() throws -> [StreamDelta] {
        var output:[StreamDelta]=[]
        if !pendingLine.isEmpty {
            guard let text=String(bytes:pendingLine,encoding:.utf8) else{throw AppFault("API_BAD_RESPONSE","服务返回了无效的文字编码。",retryable:true)}
            pendingLine=[];output += try line(text)
        }
        output += try line("");return output
    }
    public mutating func line(_ line: String) throws -> [StreamDelta] {
        if !line.isEmpty {if line.hasPrefix("data:"){lines.append(String(line.dropFirst(5)).trimmingCharacters(in:.whitespaces))};return []}
        guard !lines.isEmpty else{return []};let text=lines.joined(separator:"\n");lines=[]
        if text=="[DONE]" {return []}
        guard let data=text.data(using:.utf8),let json=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw AppFault("API_BAD_RESPONSE","服务返回了无法解析的数据。",retryable:true)}
        if json["error"] != nil {throw AppFault("API_BAD_RESPONSE","服务返回错误，已接收内容保留。",retryable:true)}
        guard let choices=json["choices"] as? [[String:Any]] else{return []}
        return choices.compactMap{choice in
            let delta=choice["delta"] as? [String:Any] ?? [:]
            let answer=delta["content"] as? String ?? "",reasoning=delta["reasoning_content"] as? String ?? "",finish=choice["finish_reason"] as? String
            return answer.isEmpty && reasoning.isEmpty && finish==nil ? nil:StreamDelta(answer:answer,reasoning:reasoning,finishReason:finish)
        }
    }
    public static func httpFault(_ status: Int) -> AppFault {
        switch status {
        case 401:return AppFault("AUTH_FAILED","API Key 无效，请检查设置。")
        case 402:return AppFault("INSUFFICIENT_BALANCE","DeepSeek 余额不足，请到官方平台充值。")
        case 429:return AppFault("RATE_LIMITED","请求过于频繁，请稍后手动重试。",retryable:true)
        default:return AppFault(status>=500 ? "NETWORK_ERROR":"API_BAD_RESPONSE",status>=500 ? "DeepSeek 暂时不可用，请稍后重试。":"服务拒绝了此请求，请检查模型与资料。",retryable:status>=500)
        }
    }
}
