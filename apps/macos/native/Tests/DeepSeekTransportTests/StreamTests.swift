import Foundation
import Testing
import ReadingCore
@testable import DeepSeekTransport
@Suite struct StreamTests {
    @Test func fragmentsReasoningAndCompletion() throws {
        var decoder=SSEDecoder()
        #expect(try decoder.line(": keepalive").isEmpty)
        _=try decoder.line("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"分析\"}}]}")
        #expect(try decoder.line("")==[StreamDelta(reasoning:"分析")])
        _=try decoder.line("data: {\"choices\":[{\"delta\":{\"content\":\"结论\"},\"finish_reason\":\"stop\"}]}")
        #expect(try decoder.line("")==[StreamDelta(answer:"结论",finishReason:"stop")])
        _=try decoder.line("data: [DONE]");#expect(try decoder.line("").isEmpty)
    }
    @Test func badJSONAndHTTPMapping() throws {
        var decoder=SSEDecoder();_=try decoder.line("data: broken")
        #expect(throws:AppFault.self){try decoder.line("")}
        #expect(SSEDecoder.httpFault(401).code=="AUTH_FAILED");#expect(SSEDecoder.httpFault(402).code=="INSUFFICIENT_BALANCE");#expect(SSEDecoder.httpFault(429).code=="RATE_LIMITED")
    }
    @Test func rawByteFramesPreserveBlankLinesAndSplitUTF8() throws {
        let wire=": keepalive\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"中文\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        var decoder=SSEDecoder(),deltas:[StreamDelta]=[]
        for byte in wire.utf8 {deltas += try decoder.feed(byte)}
        deltas += try decoder.finish()
        #expect(deltas==[StreamDelta(answer:"中文"),StreamDelta(finishReason:"stop")])
    }
    @Test func invalidUTF8DoesNotMasqueradeAsValidOutput() throws {
        var decoder=SSEDecoder();_=try decoder.feed(0xff)
        #expect(throws:AppFault.self){try decoder.feed(10)}
    }
    actor TestVault:CredentialReader {func readForRequest()->String{"only-a-test-value"}}
    @Test func releasedLeaseCannotStartNetwork() async throws {
        let transport=RequestCoordinator(vault:TestVault()),lease=try await transport.acquire(preparationId:newID())
        await transport.release(lease)
        await #expect(throws:AppFault.self){try await transport.stream(requestId:newID(),body:Data(),lease:lease)}
    }
}
