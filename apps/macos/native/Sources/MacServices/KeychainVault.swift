import Foundation
import Security
import LocalAuthentication
import ReadingCore
public actor KeychainVault: CredentialReader {
    private let service: String
    public init(service: String = "com.decous.anysidebar.mac.deepseek") {self.service=service}
    private var query:[String:Any] {[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"default",kSecAttrSynchronizable as String:false]}
    public func configured() throws -> Bool {
        var q=query;q[kSecReturnAttributes as String]=true;let context=LAContext();context.interactionNotAllowed=true;q[kSecUseAuthenticationContext as String]=context
        var result:CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound{return false};guard status==errSecSuccess else{throw AppFault("CREDENTIAL_ACCESS_DENIED","无法检查钥匙串状态，请检查系统授权。",retryable:true)};return true
    }
    public func replace(_ key: String) throws {
        let key=key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !key.isEmpty,key.count<=4096,!key.contains("\n"),!key.contains("\r") else{throw AppFault("INVALID_ARGUMENT","API Key 格式无效。")}
        let values:[String:Any]=[kSecValueData as String:Data(key.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status=SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if status==errSecItemNotFound {var add=query;values.forEach{add[$0]=$1};status=SecItemAdd(add as CFDictionary,nil)}
        guard status==errSecSuccess else{throw AppFault("CREDENTIAL_ACCESS_DENIED","钥匙串拒绝保存，原设置未删除。",retryable:true)}
    }
    public func clear() throws {let status=SecItemDelete(query as CFDictionary);guard status==errSecSuccess || status==errSecItemNotFound else{throw AppFault("CREDENTIAL_ACCESS_DENIED","无法删除钥匙串凭据。",retryable:true)}}
    public func readForRequest() throws -> String {
        var q=query;q[kSecReturnData as String]=true
        var result:CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound{throw AppFault("CREDENTIAL_REQUIRED","请先填写 API Key。")}
        guard status==errSecSuccess,let data=result as? Data,let key=String(data:data,encoding:.utf8),!key.isEmpty else{throw AppFault("CREDENTIAL_ACCESS_DENIED","钥匙串访问被拒绝或不可用，请检查系统授权。",retryable:true)};return key
    }
}
