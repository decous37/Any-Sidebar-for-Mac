import Foundation
import Testing
@testable import ReadingCore
@Suite struct FoundationContractsTests {
    @Test func identifiers() { #expect(validID(newID())); #expect(!validID("../private")); #expect(now() > 0) }
    @Test func faultRoundTrip() throws {
        let fault=AppFault("REVISION_CONFLICT","请重新载入。",currentRevision:3)
        #expect(try JSONDecoder().decode(AppFault.self,from:JSONEncoder().encode(fault)) == fault)
    }
    @Test func redactedSource() throws {
        let source=SourceInfo(kind:"external-selection",documentIdentity:"/private/secret.pdf")
        let encoded=try JSONEncoder().encode(SourceView(source))
        #expect(!String(decoding:encoded,as:UTF8.self).contains("secret"))
    }
}
