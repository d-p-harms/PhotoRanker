import UIKit
import Security

class DeviceIdManager {
    static let shared = DeviceIdManager()
    private let key = "com.photoranker.deviceId"

    private init() {}

    func deviceId() -> String {
        if let existing = readId() {
            return existing
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        saveId(newId)
        return newId
    }

    private func readId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }

    private func saveId(_ id: String) {
        let data = id.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
