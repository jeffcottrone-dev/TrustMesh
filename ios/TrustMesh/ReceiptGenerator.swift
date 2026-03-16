import Foundation
import CryptoKit

final class ReceiptGenerator {
    static let shared = ReceiptGenerator()

    private let backendURL = "https://trustmesh-production.up.railway.app"

    private init() {}

    // MARK: - Generate receipt

    func generateReceipt(actionText: String) async throws -> Receipt {
        let keyManager = KeyManager.shared

        // 1. SHA-256 hash of action text
        let actionData = Data(actionText.utf8)
        let actionHash = SHA256.hash(data: actionData)
            .map { String(format: "%02x", $0) }
            .joined()

        // 2. Unix timestamp in milliseconds
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // 3. Device ID
        let deviceID = keyManager.deviceID()

        // 4. Random 16-byte session nonce
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &nonceBytes)
        let sessionNonce = nonceBytes.map { String(format: "%02x", $0) }.joined()

        // 5. Build commitment
        let commitment = ActionCommitment(
            actionHash: actionHash,
            timestamp: timestamp,
            deviceID: deviceID,
            sessionNonce: sessionNonce,
            biometricModality: "face"
        )

        // 6. JSON encode with sorted keys
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let commitmentData = try encoder.encode(commitment)

        // 7. Sign with Face ID + Secure Enclave
        let signatureData = try await keyManager.sign(data: commitmentData)

        // 8. Build receipt
        let receipt = Receipt(
            commitment: commitment,
            signature: signatureData.base64EncodedString(),
            publicKey: keyManager.publicKeyHex
        )

        return receipt
    }

    // MARK: - Register device with backend

    func registerDeviceIfNeeded() async {
        let key = "trustmesh.device.registered"
        if UserDefaults.standard.bool(forKey: key) {
            print("ReceiptGenerator: device already registered")
            return
        }

        let keyManager = KeyManager.shared
        let deviceID = keyManager.deviceID()
        let publicKey = keyManager.publicKeyBase64

        guard !deviceID.isEmpty, !publicKey.isEmpty else {
            print("ReceiptGenerator: no key available, skipping registration")
            return
        }

        let url = URL(string: "\(backendURL)/keys")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "deviceID": deviceID,
            "publicKey": publicKey
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                UserDefaults.standard.set(true, forKey: key)
                print("ReceiptGenerator: device registered successfully")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                print("ReceiptGenerator: registration response: \(body)")
            }
        } catch {
            print("ReceiptGenerator: registration failed: \(error)")
        }

        // Verify by fetching our own key
        do {
            let lookupURL = URL(string: "\(backendURL)/keys/\(deviceID)")!
            let (data, _) = try await URLSession.shared.data(from: lookupURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            print("ReceiptGenerator: backend lookup: \(body)")
        } catch {
            print("ReceiptGenerator: lookup failed: \(error)")
        }
    }
}
