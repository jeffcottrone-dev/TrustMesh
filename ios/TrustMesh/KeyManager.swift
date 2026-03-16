import Foundation
import CryptoKit
import LocalAuthentication

final class KeyManager {
    static let shared = KeyManager()

    private let keyTag = "com.trustmesh.secureenclave.signing"
    private var privateKey: SecureEnclave.P256.Signing.PrivateKey?

    private init() {
        loadOrCreateKey()
    }

    // MARK: - Key lifecycle

    private func loadOrCreateKey() {
        // Try to load existing key
        if let stored = UserDefaults.standard.data(forKey: keyTag) {
            do {
                privateKey = try SecureEnclave.P256.Signing.PrivateKey(
                    dataRepresentation: stored
                )
                return
            } catch {
                print("KeyManager: failed to load stored key, creating new one: \(error)")
            }
        }

        // Create new Secure Enclave key
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            privateKey = key
            UserDefaults.standard.set(key.dataRepresentation, forKey: keyTag)
            print("KeyManager: new Secure Enclave key created")
        } catch {
            print("KeyManager: failed to create Secure Enclave key: \(error)")
        }
    }

    // MARK: - Public key (hex-encoded DER)

    var publicKeyHex: String {
        guard let key = privateKey else { return "" }
        return key.publicKey.derRepresentation.map {
            String(format: "%02x", $0)
        }.joined()
    }

    var publicKeyBase64: String {
        guard let key = privateKey else { return "" }
        return key.publicKey.derRepresentation.base64EncodedString()
    }

    // MARK: - Device ID (SHA-256 of public key, first 16 hex chars)

    func deviceID() -> String {
        guard let key = privateKey else { return "" }
        let hash = SHA256.hash(data: key.publicKey.derRepresentation)
        return hash.map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    // MARK: - Sign with Face ID

    func sign(data: Data) async throws -> Data {
        guard let storedData = UserDefaults.standard.data(forKey: keyTag) else {
            throw KeyManagerError.noKey
        }

        let context = LAContext()
        context.localizedReason = "Authorize this action"

        // Check biometrics available
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        ) else {
            throw KeyManagerError.biometricsUnavailable(
                error?.localizedDescription ?? "Unknown error"
            )
        }

        // Prompt Face ID
        try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Sign authorization receipt"
        )

        // Load key with authenticated context
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: storedData,
            authenticationContext: context
        )

        let signature = try key.signature(for: data)
        return signature.derRepresentation
    }
}

enum KeyManagerError: LocalizedError {
    case noKey
    case biometricsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No signing key found"
        case .biometricsUnavailable(let reason):
            return "Biometrics unavailable: \(reason)"
        }
    }
}
