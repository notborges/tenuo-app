import Foundation
import Security

enum LicenseStoreError: LocalizedError {
    case unableToRead
    case unableToSave
    case unableToDelete

    var errorDescription: String? {
        switch self {
        case .unableToRead: return "Tenuo could not read the license from Keychain."
        case .unableToSave: return "Tenuo could not save the license in Keychain."
        case .unableToDelete: return "Tenuo could not remove the license from Keychain."
        }
    }
}

protocol LicenseStore {
    func load() throws -> LicenseRecord?
    func save(_ record: LicenseRecord) throws
    func remove() throws
}

final class KeychainLicenseStore: LicenseStore {
    private let service: String
    private let account = "license"

    init(service: String = Bundle.main.bundleIdentifier ?? "app.tenuo") {
        self.service = service
    }

    func load() throws -> LicenseRecord? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
            let data = item as? Data,
            let record = try? JSONDecoder().decode(LicenseRecord.self, from: data)
        else { throw LicenseStoreError.unableToRead }
        return record
    }

    func save(_ record: LicenseRecord) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(record)
        } catch {
            throw LicenseStoreError.unableToSave
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw LicenseStoreError.unableToSave
        }

        var item = baseQuery
        item.merge(attributes) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw LicenseStoreError.unableToSave
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseStoreError.unableToDelete
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
