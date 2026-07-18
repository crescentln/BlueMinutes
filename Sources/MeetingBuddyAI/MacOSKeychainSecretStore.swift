import Foundation
import MeetingBuddyApplication
import Security

public enum KeychainSecretStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(Int32)
    case valueTooLarge
}

/// Generic-password storage backed by the user's macOS Keychain. Values never enter app logs or SQLite.
public final class MacOSKeychainSecretStore: SecretStore, @unchecked Sendable {
    public static let maximumValueBytes = 64 * 1_024

    public init() {}

    public func read(_ identifier: SecretIdentifier) throws -> Data? {
        var query = baseQuery(identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
        return data
    }

    public func write(_ value: Data, for identifier: SecretIdentifier) throws {
        guard !value.isEmpty, value.count <= Self.maximumValueBytes else {
            throw KeychainSecretStoreError.valueTooLarge
        }
        let query = baseQuery(identifier)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: value] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(updateStatus)
        }
        var attributes = query
        attributes[kSecValueData as String] = value
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(addStatus)
        }
    }

    public func remove(_ identifier: SecretIdentifier) throws {
        let status = SecItemDelete(baseQuery(identifier) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ identifier: SecretIdentifier) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identifier.service,
            kSecAttrAccount as String: identifier.account
        ]
    }
}
