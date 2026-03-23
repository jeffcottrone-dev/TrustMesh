//
//  KeyPinStore.swift
//  TrustMesh
//

import Foundation
import Security

final class KeyPinStore {
    static let shared = KeyPinStore()

    private let service = "com.trustmesh.keypins"

    private init() {}

    // MARK: - Pin a public key for a device ID

    /// Stores the first-seen public key for a device. Returns true if this is a new pin.
    func pin(deviceID: String, publicKey: String) -> Bool {
        if let existing = getPinnedKey(deviceID: deviceID) {
            // Already pinned — return false (no change)
            return existing != publicKey  // true if key changed (warning case)
        }
        // First time seeing this device — pin the key
        save(deviceID: deviceID, publicKey: publicKey)
        return false
    }

    /// Check if a key matches the pinned key. Returns nil if no pin exists.
    func verify(deviceID: String, publicKey: String) -> KeyPinResult {
        guard let pinned = getPinnedKey(deviceID: deviceID) else {
            // First time — pin it
            save(deviceID: deviceID, publicKey: publicKey)
            return .firstSeen
        }
        if pinned == publicKey {
            return .match
        } else {
            return .mismatch(pinnedKey: String(pinned.prefix(16)), serverKey: String(publicKey.prefix(16)))
        }
    }

    // MARK: - Keychain operations

    private func getPinnedKey(deviceID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(deviceID: String, publicKey: String) {
        let data = Data(publicKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecValueData as String: data,
        ]
        // Delete existing if any, then add
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}

enum KeyPinResult {
    case firstSeen      // Key pinned for the first time
    case match          // Key matches what we pinned
    case mismatch(pinnedKey: String, serverKey: String)  // Key changed — possible attack
}
