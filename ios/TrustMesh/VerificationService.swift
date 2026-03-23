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

enum MessageVerificationResult {
    case valid(sender: String, channel: String, timestamp: Date, message: String?)
    case invalid(reason: String)
}

final class VerificationService {
    static let shared = VerificationService()

    private let backendURL = "https://trustmesh-production.up.railway.app"

    private init() {}

    // MARK: - Receipt Verification

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

    // MARK: - Message Verification (by artifact JSON — local P-256 verify)

    func verifyMessage(artifact: VerifiedMessageArtifact, receivedText: String) async -> MessageVerificationResult {
        // Step 1: Hash the received text and compare to signed messageHash
        let receivedHash = SHA256.hash(data: Data(receivedText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        if receivedHash != artifact.commitment.messageHash {
            return .invalid(reason: "Message was tampered with — text does not match what was signed")
        }

        // Step 2: Verify P-256 signature
        let deviceID = artifact.commitment.senderID

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

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let commitmentData: Data
        do {
            commitmentData = try encoder.encode(artifact.commitment)
        } catch {
            return .invalid(reason: "Could not encode commitment")
        }

        guard let pubKeyData = Data(base64Encoded: serverPublicKeyBase64) else {
            return .invalid(reason: "Invalid public key format")
        }
        guard let signatureData = Data(base64Encoded: artifact.signature) else {
            return .invalid(reason: "Invalid signature format")
        }

        do {
            let publicKey = try P256.Signing.PublicKey(derRepresentation: pubKeyData)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            let isValid = publicKey.isValidSignature(signature, for: commitmentData)

            if isValid {
                let timestamp = Date(timeIntervalSince1970: Double(artifact.commitment.timestamp) / 1000.0)
                let senderName = await fetchSenderName(deviceID: deviceID) ?? "Device \(String(deviceID.prefix(8)))..."
                return .valid(
                    sender: senderName,
                    channel: artifact.commitment.channel,
                    timestamp: timestamp,
                    message: artifact.message
                )
            } else {
                return .invalid(reason: "Signature does not match — message was tampered with")
            }
        } catch {
            return .invalid(reason: "Verification failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Verification (by URL — server-side verify)

    func verifyMessageByURL(url: String, receivedText: String) async -> MessageVerificationResult {
        guard let urlObj = URL(string: url),
              let messageId = urlObj.pathComponents.last, !messageId.isEmpty else {
            return .invalid(reason: "Invalid verification URL")
        }

        return await verifyMessageById(messageId, receivedText: receivedText)
    }

    // MARK: - Message Verification (by ID — server-side verify)

    func verifyMessageById(_ messageId: String, receivedText: String) async -> MessageVerificationResult {
        guard let url = URL(string: "\(backendURL)/messages/\(messageId)/verify") else {
            return .invalid(reason: "Invalid message ID")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["receivedText": receivedText]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMsg = errorData?["error"] as? String ?? "Message not found on server"
                return .invalid(reason: errorMsg)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let isValid = json?["valid"] as? Bool ?? false
            let textMatch = json?["textMatch"] as? Bool ?? false

            if !textMatch {
                let reason = json?["reason"] as? String ?? "Message text does not match what was signed"
                return .invalid(reason: reason)
            }

            if isValid {
                let sender = json?["sender"] as? String ?? "Unknown"
                let channel = json?["channel"] as? String ?? "unknown"
                let messageText = json?["messageText"] as? String
                let createdAt = json?["createdAt"] as? String
                let timestamp: Date
                if let dateStr = createdAt {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    timestamp = formatter.date(from: dateStr) ?? Date()
                } else {
                    timestamp = Date()
                }

                return .valid(sender: sender, channel: channel, timestamp: timestamp, message: messageText)
            } else {
                let error = json?["error"] as? String ?? "Signature verification failed"
                return .invalid(reason: error)
            }
        } catch {
            return .invalid(reason: "Could not reach server: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func fetchSenderName(deviceID: String) async -> String? {
        guard let url = URL(string: "\(backendURL)/senders/\(deviceID)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["displayName"] as? String
        } catch {
            return nil
        }
    }
}
