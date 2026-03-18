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
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.tmNavy.ignoresSafeArea())
                } else {
                    receiptList
                }
            }
            .navigationTitle("Receipt History")
            .navyTheme()
            .sheet(item: $selectedReceipt) { stored in
                ReceiptView(receipt: stored.receipt, actionText: stored.actionText)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 50))
                .foregroundColor(.tmSilver)
            Text("No Receipts Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text("Authorized actions will appear here")
                .font(.subheadline)
                .foregroundColor(.tmSilver)
        }
    }

    private var receiptList: some View {
        List {
            ForEach(store.receipts) { stored in
                Button { selectedReceipt = stored } label: {
                    receiptRow(stored)
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tmNavy.ignoresSafeArea())
    }

    private func receiptRow(_ stored: StoredReceipt) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stored.actionText)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(formatDate(stored.storedAt))
                        .font(.caption)
                        .foregroundColor(.tmSilver)

                    if let recipient = stored.recipient, !recipient.isEmpty {
                        Text("Sent to \(recipient)")
                            .font(.caption)
                            .foregroundColor(.tmBlue)
                    }

                    if let refID = stored.referenceID, !refID.isEmpty {
                        Text("Session: \(refID)")
                            .font(.caption)
                            .foregroundColor(.tmBlue)
                    }
                }
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
