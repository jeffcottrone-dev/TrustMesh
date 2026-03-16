//
//  HistoryView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

struct HistoryView: View {
    var store = ReceiptStore.shared
    @State private var selectedReceipt: StoredReceipt?

    var body: some View {
        NavigationStack {
            Group {
                if store.receipts.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No Receipts Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Authorized actions will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.receipts) { stored in
                            Button(action: {
                                selectedReceipt = stored
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stored.actionText)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)

                                        HStack(spacing: 8) {
                                            Text(formatDate(stored.storedAt))
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            if let recipient = stored.recipient, !recipient.isEmpty {
                                                Text("Sent to \(recipient)")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }

                                            if let refID = stored.referenceID, !refID.isEmpty {
                                                Text("Session: \(refID)")
                                                    .font(.caption)
                                                    .foregroundColor(.purple)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Receipt History")
            .sheet(item: $selectedReceipt) { stored in
                ReceiptView(receipt: stored.receipt, actionText: stored.actionText)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
