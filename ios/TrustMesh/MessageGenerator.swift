//
//  MessageGenerator.swift
//  TrustMesh
//

import Foundation
import CryptoKit
import UIKit

final class MessageGenerator {
    static let shared = MessageGenerator()

    private let backendURL = "https://trustmesh-production.up.railway.app"
    private let senderRegisteredKey = "trustmesh.sender.registered"

    private init() {}

    // MARK: - Generate signed message

    func generateSignedMessage(messageText: String, channel: MessageChannel, includeText: Bool = true, context: String? = nil, orgID: String? = nil) async throws -> VerifiedMessageArtifact {
        let keyManager = KeyManager.shared

        // Auto-register sender on first message sign
        if !UserDefaults.standard.bool(forKey: senderRegisteredKey) {
            let deviceName = await UIDevice.current.name
            await registerSenderIfNeeded(displayName: deviceName, channels: MessageChannel.allCases.map(\.rawValue))
            UserDefaults.standard.set(true, forKey: senderRegisteredKey)
        }

        // 1. SHA-256 hash of message text
        let messageData = Data(messageText.utf8)
        let messageHash = SHA256.hash(data: messageData)
            .map { String(format: "%02x", $0) }
            .joined()

        // 2. Unix timestamp in milliseconds
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // 3. Device ID
        let deviceID = keyManager.deviceID()

        // 4. Random nonce (UUID)
        let nonce = UUID().uuidString

        // 5. Build commitment
        let commitment = MessageCommitment(
            version: 1,
            senderID: deviceID,
            channel: channel.rawValue,
            messageHash: messageHash,
            timestamp: timestamp,
            nonce: nonce,
            context: context,
            orgID: orgID
        )

        // 6. JSON encode with sorted keys (must match server verification)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let commitmentData = try encoder.encode(commitment)

        // 7. Sign with Face ID + Secure Enclave
        let signatureData = try await keyManager.sign(data: commitmentData)

        // 8. Generate message ID
        let messageId = UUID().uuidString

        // 9. Build artifact (without verification URL yet)
        var artifact = VerifiedMessageArtifact(
            messageId: messageId,
            commitment: commitment,
            message: includeText ? messageText : nil,
            signature: signatureData.base64EncodedString(),
            publicKeyHint: String(keyManager.publicKeyHex.prefix(16)),
            verificationURL: nil
        )

        // 10. POST to server and get verification URL
        let commitmentJSON = String(data: commitmentData, encoding: .utf8) ?? "{}"
        artifact = try await postToServer(artifact: artifact, commitmentJSON: commitmentJSON)

        return artifact
    }

    // MARK: - Post to server

    private func postToServer(artifact: VerifiedMessageArtifact, commitmentJSON: String) async throws -> VerifiedMessageArtifact {
        let url = URL(string: "\(backendURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "messageId": artifact.messageId,
            "deviceID": artifact.commitment.senderID,
            "channel": artifact.commitment.channel,
            "messageHash": artifact.commitment.messageHash,
            "messageText": artifact.message as Any,
            "commitment": commitmentJSON,
            "signature": artifact.signature,
            "publicKeyHint": artifact.publicKeyHint,
        ]
        if let orgID = artifact.commitment.orgID {
            body["orgID"] = orgID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let respBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw MessageError.serverError(respBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let verificationURL = json?["verificationURL"] as? String

        return VerifiedMessageArtifact(
            messageId: artifact.messageId,
            commitment: artifact.commitment,
            message: artifact.message,
            signature: artifact.signature,
            publicKeyHint: artifact.publicKeyHint,
            verificationURL: verificationURL
        )
    }

    // MARK: - Register sender profile

    func registerSenderIfNeeded(displayName: String, channels: [String]) async {
        let keyManager = KeyManager.shared
        let deviceID = keyManager.deviceID()
        guard !deviceID.isEmpty else { return }

        let url = URL(string: "\(backendURL)/senders")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceID": deviceID,
            "displayName": displayName,
            "channels": channels,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                print("MessageGenerator: sender registered")
            } else {
                let respBody = String(data: data, encoding: .utf8) ?? ""
                print("MessageGenerator: sender registration response: \(respBody)")
            }
        } catch {
            print("MessageGenerator: sender registration failed: \(error)")
        }
    }
}

enum MessageError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let detail):
            return "Server error: \(detail)"
        }
    }
}
