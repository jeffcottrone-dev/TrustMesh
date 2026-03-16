//
//  ReceiptStore.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import Foundation
import Observation

struct StoredReceipt: Codable, Identifiable {
    var id: String { receipt.commitment.sessionNonce }
    let receipt: Receipt
    let actionText: String
    let recipient: String?
    let referenceID: String?
    let storedAt: Date
}

@Observable
final class ReceiptStore {
    static let shared = ReceiptStore()

    var receipts: [StoredReceipt] = []

    private let key = "trustmesh.receipt.history"

    private init() {
        load()
    }

    func save(receipt: Receipt, actionText: String, recipient: String? = nil, referenceID: String? = nil) {
        let stored = StoredReceipt(
            receipt: receipt,
            actionText: actionText,
            recipient: recipient,
            referenceID: referenceID,
            storedAt: Date()
        )
        receipts.insert(stored, at: 0)
        persist()
    }

    func clear() {
        receipts.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        receipts = (try? JSONDecoder().decode([StoredReceipt].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
