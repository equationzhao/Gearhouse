import Foundation
#if canImport(GearhouseCore)
import GearhouseCore
#endif
#if os(iOS)
import Security
struct KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String
    init(service: String = "com.gearhouse.ios", account: String = "intervals-api-key") {
        self.service = service
        self.account = account
    }
    func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    func remove() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#else
struct KeychainSecretStore: SecretStore { func read() -> String? { nil }; func write(_ value: String) throws {}; func remove() throws {} }
#endif

#if os(iOS)
struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        if status == errSecMissingEntitlement {
            return "当前 App 缺少钥匙串签名权限，请安装修复后的版本。"
        }
        return "无法保存到钥匙串（\(status)），请重试。"
    }
}

#if DEBUG
/// Exercises the app's actual keychain entitlement without touching its API key.
enum KeychainSelfTest {
    static func run() {
        let store = KeychainSecretStore(service: "com.gearhouse.ios.self-test", account: UUID().uuidString)
        var report: [String: String] = [:]
        do {
            try store.write("non-secret-probe")
            report["insert"] = "passed"
            report["read"] = store.read() == "non-secret-probe" ? "passed" : "failed"
            try store.write("updated-non-secret-probe")
            report["update"] = store.read() == "updated-non-secret-probe" ? "passed" : "failed"
            try store.remove()
            report["delete"] = store.read() == nil ? "passed" : "failed"
        } catch let failure {
            report["error"] = failure.localizedDescription
            if let failure = failure as? KeychainError { report["status"] = String(failure.status) }
            try? store.remove()
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gearhouse")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("keychain-self-test.json"), options: .atomic)
        } catch { NSLog("Keychain self-test report could not be written") }
    }
}
#endif
#endif
