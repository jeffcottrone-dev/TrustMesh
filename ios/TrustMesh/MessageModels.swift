//
//  MessageModels.swift
//  TrustMesh
//

import Foundation

struct MessageCommitment: Codable {
    let version: Int           // 1
    let senderID: String       // deviceID
    let channel: String        // sms/email/phone/other
    let messageHash: String    // SHA-256 hex
    let timestamp: Int64       // Unix ms
    let nonce: String          // random UUID
    let context: String?       // optional
}

struct VerifiedMessageArtifact: Codable, Identifiable {
    var id: String { messageId }
    let messageId: String
    let commitment: MessageCommitment
    let message: String?       // optional plaintext
    let signature: String      // base64 DER
    let publicKeyHint: String
    let verificationURL: String?
}

enum MessageChannel: String, CaseIterable, Codable {
    case sms = "sms"
    case email = "email"
    case phone = "phone"
    case other = "other"

    var label: String {
        switch self {
        case .sms: return "SMS"
        case .email: return "Email"
        case .phone: return "Phone"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .sms: return "message.fill"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
