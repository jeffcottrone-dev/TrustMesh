//
//  MessageStore.swift
//  TrustMesh
//

import Foundation
import Observation

struct StoredMessage: Codable, Identifiable {
    var id: String { artifact.messageId }
    let artifact: VerifiedMessageArtifact
    let messageText: String
    let channel: String
    let storedAt: Date
}

@Observable
final class MessageStore {
    static let shared = MessageStore()

    var messages: [StoredMessage] = []

    private let key = "trustmesh.message.history"

    private init() {
        load()
    }

    func save(artifact: VerifiedMessageArtifact, messageText: String, channel: String) {
        let stored = StoredMessage(
            artifact: artifact,
            messageText: messageText,
            channel: channel,
            storedAt: Date()
        )
        messages.insert(stored, at: 0)
        persist()
    }

    func clear() {
        messages.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        messages = (try? JSONDecoder().decode([StoredMessage].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
