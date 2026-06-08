import Foundation
import Security

public enum KeychainServiceNamespace {
    public static let current = "com.ytlll.NewCodexBar"
    public static let legacy = "com.steipete.CodexBar"
    public static let currentCache = "com.ytlll.NewCodexBar.cache"
    public static let legacyCache = "com.steipete.codexbar.cache"

    private static let log = CodexBarLog.logger("keychain-namespace")

    /// Reads from `current` namespace first. Falls back to `legacy` and silently copies
    /// the item to `current` when found in legacy. Does NOT delete the legacy entry.
    public static func readWithLegacyFallback(account: String) throws -> (data: Data?, didMigrate: Bool) {
        if let data = try read(service: current, account: account) {
            return (data, false)
        }
        guard let legacyData = try read(service: legacy, account: account) else {
            return (nil, false)
        }
        try write(data: legacyData, service: current, account: account)
        log.debug("Migrated \(account) from legacy to current namespace")
        return (legacyData, true)
    }

    private static func read(service: String, account: String) throws -> Data? {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainNamespaceError.readFailed(status)
        }
        return result as? Data
    }

    private static func write(data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainNamespaceError.writeFailed(updateStatus)
        }
        var addQuery = query
        for (key, value) in attributes { addQuery[key] = value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainNamespaceError.writeFailed(addStatus)
        }
    }
}

public enum KeychainNamespaceError: LocalizedError {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .readFailed(status): "Keychain namespace read failed: \(status)"
        case let .writeFailed(status): "Keychain namespace write failed: \(status)"
        }
    }
}
