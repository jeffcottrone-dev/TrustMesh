//
//  HistoryView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

enum HistoryTab: String, CaseIterable {
    case receipts = "Receipts"
    case messages = "Messages"
}

struct HistoryView: View {
    var receiptStore = ReceiptStore.shared
    var messageStore = MessageStore.shared
    @State private var selectedTab: HistoryTab = .receipts
    @State private var selectedReceipt: StoredReceipt?
    @State private var selectedMessage: StoredMessage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(HistoryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    switch selectedTab {
                    case .receipts:
                        if receiptStore.receipts.isEmpty {
                            emptyState(icon: "clock.arrow.circlepath", title: "No Receipts Yet", subtitle: "Authorized actions will appear here")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.tmNavy.ignoresSafeArea())
                        } else {
                            receiptList
                        }
                    case .messages:
                        if messageStore.messages.isEmpty {
                            emptyState(icon: "envelope.badge.shield.half.filled", title: "No Messages Yet", subtitle: "Signed messages will appear here")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.tmNavy.ignoresSafeArea())
                        } else {
                            messageList
                        }
                    }
                }
            }
            .background(Color.tmNavy.ignoresSafeArea())
            .navigationTitle("History")
            .navyTheme()
            .sheet(item: $selectedReceipt) { stored in
                ReceiptView(receipt: stored.receipt, actionText: stored.actionText)
            }
            .sheet(item: $selectedMessage) { stored in
                MessageArtifactView(
                    artifact: stored.artifact,
                    messageText: stored.messageText,
                    channel: MessageChannel(rawValue: stored.channel) ?? .other
                )
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.tmSilver)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.tmSilver)
        }
    }

    // MARK: - Receipt List

    private var receiptList: some View {
        List {
            ForEach(receiptStore.receipts) { stored in
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

    // MARK: - Message List

    private var messageList: some View {
        List {
            ForEach(messageStore.messages) { stored in
                Button { selectedMessage = stored } label: {
                    messageRow(stored)
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tmNavy.ignoresSafeArea())
    }

    private func messageRow(_ stored: StoredMessage) -> some View {
        HStack {
            let ch = MessageChannel(rawValue: stored.channel) ?? .other
            Image(systemName: ch.icon)
                .foregroundColor(.tmBlue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(stored.messageText)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(formatDate(stored.storedAt))
                        .font(.caption)
                        .foregroundColor(.tmSilver)

                    Text(ch.label)
                        .font(.caption)
                        .foregroundColor(.tmBlue)
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
