//
//  TransparencyLogView.swift
//  TrustMesh
//

import SwiftUI

struct TransparencyLogEntry: Codable, Identifiable {
    var id: Int { sequenceNum }
    let sequenceNum: Int
    let action: String
    let entityType: String
    let entityID: String
    let dataHash: String
    let previousHash: String
    let timestamp: String
}

struct TransparencyLogView: View {
    @State private var entries: [TransparencyLogEntry] = []
    @State private var chainValid: Bool?
    @State private var isLoading = true

    private let backendURL = "https://trustmesh-production.up.railway.app"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Chain status banner
                    if let valid = chainValid {
                        HStack(spacing: 8) {
                            Image(systemName: valid ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(valid ? .green : .red)
                            Text(valid ? "Hash chain is intact" : "Hash chain broken — tampering detected")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(valid ? .green : .red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((valid ? Color.green : Color.red).opacity(0.15))
                    }

                    if isLoading {
                        Spacer()
                        ProgressView().tint(.tmBlue).scaleEffect(1.5)
                        Spacer()
                    } else if entries.isEmpty {
                        Spacer()
                        Text("No log entries yet")
                            .foregroundColor(.tmSilver)
                        Spacer()
                    } else {
                        List(entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(entry.sequenceNum)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.tmBlue)
                                    Text(entry.action)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(entry.entityType)
                                        .font(.caption2)
                                        .foregroundColor(.tmSilver)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                Text("Entity: \(String(entry.entityID.prefix(16)))...")
                                    .font(.caption2)
                                    .foregroundColor(.tmSilver)
                                    .fontDesign(.monospaced)
                                Text("Hash: \(String(entry.dataHash.prefix(24)))...")
                                    .font(.caption2)
                                    .foregroundColor(.tmSilver)
                                    .fontDesign(.monospaced)
                                Text(entry.timestamp)
                                    .font(.caption2)
                                    .foregroundColor(.tmSilver)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Transparency Log")
            .navigationBarTitleDisplayMode(.inline)
            .navyTheme()
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        // Load log entries and verify chain in parallel
        async let entriesTask: () = loadEntries()
        async let verifyTask: () = verifyChain()
        _ = await (entriesTask, verifyTask)
        isLoading = false
    }

    private func loadEntries() async {
        guard let url = URL(string: "\(backendURL)/transparency/log?limit=100") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let entriesData = json?["entries"] {
                let entriesJSON = try JSONSerialization.data(withJSONObject: entriesData)
                entries = try JSONDecoder().decode([TransparencyLogEntry].self, from: entriesJSON)
                entries.reverse()  // newest first
            }
        } catch {
            print("TransparencyLog: load failed: \(error)")
        }
    }

    private func verifyChain() async {
        guard let url = URL(string: "\(backendURL)/transparency/verify") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            chainValid = json?["valid"] as? Bool ?? false
        } catch {
            chainValid = false
        }
    }
}
