//
//  VerificationService.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import Foundation
import CryptoKit

enum VerificationResult {
    case valid(action: String, timestamp: Date, deviceID: String)
    case invalid(reason: String)
}

final class VerificationService {
    static let shared = VerificationService()

    private let backendURL = "https://trustmesh-production.up.railway.app"

    private init() {}

    func verifyReceipt(json: String) async -> VerificationResult {
        // 1. Parse JSON into Receipt
        guard let data = json.data(using: .utf8) else {
            return .invalid(reason: "Invalid JSON string")
        }

        let receipt: Receipt
        do {
            receipt = try JSONDecoder().decode(Receipt.self, from: data)
        } catch {
            return .invalid(reason: "Could not parse receipt: \(error.localizedDescription)")
        }

        // 2. Fetch public key from backend
        let deviceID = receipt.commitment.deviceID
        guard let url = URL(string: "\(backendURL)/keys/\(deviceID)") else {
            return .invalid(reason: "Invalid device ID")
        }

        let serverPublicKeyBase64: String
        do {
            let (responseData, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .invalid(reason: "Device not registered on server")
            }
            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            guard let pubKey = json?["publicKey"] as? String else {
                return .invalid(reason: "No public key in server response")
            }
            serverPublicKeyBase64 = pubKey
        } catch {
            return .invalid(reason: "Could not reach server: \(error.localizedDescription)")
        }

        // 3. Reconstruct commitment and encode with same settings
        let commitment = receipt.commitment
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let commitmentData: Data
        do {
            commitmentData = try encoder.encode(commitment)
        } catch {
            return .invalid(reason: "Could not encode commitment")
        }

        // 4. Verify signature
        guard let pubKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
            return .invalid(reason: "Invalid public key format from server")
        }

        guard let signatureData = Data(base64Encoded: receipt.signature) else {
            return .invalid(reason: "Invalid signature format")
        }

        do {
            let publicKey = try P256.Signing.PublicKey(derRepresentation: pubKeyData)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            let isValid = publicKey.isValidSignature(signature, for: commitmentData)

            if isValid {
                let timestamp = Date(timeIntervalSince1970: Double(commitment.timestamp) / 1000.0)

                // Reverse the action hash to get action text — we can't, but we confirm the signature
                return .valid(
                    action: "Cryptographically verified authorization",
                    timestamp: timestamp,
                    deviceID: deviceID
                )
            } else {
                return .invalid(reason: "Signature does not match — receipt was tampered with")
            }
        } catch {
            return .invalid(reason: "Signature verification failed: \(error.localizedDescription)")
        }
    }
}
