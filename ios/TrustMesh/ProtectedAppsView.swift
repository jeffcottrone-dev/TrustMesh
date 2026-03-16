//
//  ProtectedAppsView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

struct ProtectedApp: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let actions: [ProtectedAction]
}

struct ProtectedAction: Identifiable {
    let id = UUID()
    let label: String
    let placeholder: String
}

struct ProtectedAppsView: View {
    @State private var unlockedApps: Set<UUID> = []
    @State private var selectedApp: ProtectedApp?
    @State private var showAppDetail = false
    @State private var isAuthenticating = false
    @State private var authError = ""

    let apps: [ProtectedApp] = [
        ProtectedApp(
            name: "Chase Bank",
            icon: "building.columns.fill",
            color: .blue,
            actions: [
                ProtectedAction(label: "Wire Transfer", placeholder: "e.g. Wire $50,000 to Account 9876 at First National Bank"),
                ProtectedAction(label: "Pay Bills", placeholder: "e.g. Pay $2,400 rent to Greystone Properties"),
            ]
        ),
        ProtectedApp(
            name: "Coinbase",
            icon: "bitcoinsign.circle.fill",
            color: .orange,
            actions: [
                ProtectedAction(label: "Send Crypto", placeholder: "e.g. Send 1.5 BTC to bc1q...x4f8"),
                ProtectedAction(label: "Swap Assets", placeholder: "e.g. Swap 10 ETH for USDC"),
            ]
        ),
        ProtectedApp(
            name: "Robinhood",
            icon: "chart.line.uptrend.xyaxis",
            color: .green,
            actions: [
                ProtectedAction(label: "Execute Trade", placeholder: "e.g. Buy 500 shares AAPL at market"),
                ProtectedAction(label: "Withdraw Funds", placeholder: "e.g. Withdraw $25,000 to checking ••••4821"),
            ]
        ),
        ProtectedApp(
            name: "Ledger Wallet",
            icon: "lock.shield.fill",
            color: .purple,
            actions: [
                ProtectedAction(label: "Sign Transaction", placeholder: "e.g. Sign outgoing 2.0 BTC transaction"),
                ProtectedAction(label: "Export Keys", placeholder: "e.g. Export private key for wallet 0x3a...b7"),
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(apps) { app in
                        appRow(app)
                    }
                } header: {
                    Text("Face ID required to access")
                        .textCase(nil)
                }
            }
            .navigationTitle("Trust Mesh")
            .sheet(isPresented: $showAppDetail) {
                if let app = selectedApp {
                    AppDetailView(app: app)
                }
            }
            .alert("Authentication Failed", isPresented: .constant(!authError.isEmpty)) {
                Button("OK") { authError = "" }
            } message: {
                Text(authError)
            }
        }
    }

    private func appRow(_ app: ProtectedApp) -> some View {
        Button(action: { unlockApp(app) }) {
            HStack(spacing: 14) {
                Image(systemName: app.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(app.color)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(unlockedApps.contains(app.id) ? "Authorized" : "Locked — tap to unlock")
                        .font(.caption)
                        .foregroundColor(unlockedApps.contains(app.id) ? .green : .gray)
                }

                Spacer()

                Image(systemName: unlockedApps.contains(app.id) ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(unlockedApps.contains(app.id) ? .green : .red)
                    .font(.title3)
            }
            .padding(.vertical, 4)
        }
        .disabled(isAuthenticating)
    }

    private func unlockApp(_ app: ProtectedApp) {
        if unlockedApps.contains(app.id) {
            selectedApp = app
            showAppDetail = true
            return
        }

        isAuthenticating = true
        Task {
            do {
                let challenge = "Unlock \(app.name)".data(using: .utf8)!
                _ = try await KeyManager.shared.sign(data: challenge)
                unlockedApps.insert(app.id)
                selectedApp = app
                showAppDetail = true
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}

// MARK: - App Detail View

struct AppDetailView: View {
    let app: ProtectedApp
    @Environment(\.dismiss) private var dismiss
    @State private var authorizedActions: Set<UUID> = []
    @State private var pendingAction: ProtectedAction?
    @State private var actionDescription = ""
    @State private var activeReceipt: Receipt?
    @State private var activeActionLabel = ""
    @State private var showReceipt = false
    @State private var isAuthenticating = false
    @State private var authError = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.actions) { action in
                        actionRow(action)
                    }
                } header: {
                    HStack {
                        Image(systemName: app.icon)
                            .foregroundColor(app.color)
                        Text(app.name)
                    }
                    .textCase(nil)
                    .font(.headline)
                }
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $pendingAction) { action in
                actionInputSheet(for: action)
            }
            .sheet(isPresented: $showReceipt) {
                if let receipt = activeReceipt {
                    ReceiptView(receipt: receipt, actionText: activeActionLabel)
                }
            }
            .alert("Authorization Failed", isPresented: .constant(!authError.isEmpty)) {
                Button("OK") { authError = "" }
            } message: {
                Text(authError)
            }
        }
    }

    // MARK: - Action input sheet

    private func actionInputSheet(for action: ProtectedAction) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "faceid")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text(action.label)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(app.name)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe this action:")
                        .font(.headline)
                    TextField(action.placeholder, text: $actionDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding(.horizontal)

                Button(action: { submitAction(action) }) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Authorize with Face ID", systemImage: "faceid")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(actionDescription.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(actionDescription.isEmpty || isAuthenticating)

                Spacer()
            }
            .navigationTitle("Authorize Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        pendingAction = nil
                        actionDescription = ""
                    }
                }
            }
        }
    }

    private func actionRow(_ action: ProtectedAction) -> some View {
        Button(action: { tappedAction(action) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(authorizedActions.contains(action.id) ? "Authorized" : "Requires Face ID")
                        .font(.caption)
                        .foregroundColor(authorizedActions.contains(action.id) ? .green : .gray)
                }

                Spacer()

                if authorizedActions.contains(action.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "faceid")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tappedAction(_ action: ProtectedAction) {
        actionDescription = ""
        pendingAction = action
    }

    private func submitAction(_ action: ProtectedAction) {
        isAuthenticating = true
        Task {
            do {
                let fullAction = "\(action.label) — \(app.name): \(actionDescription)"
                let receipt = try await ReceiptGenerator.shared.generateReceipt(actionText: fullAction)
                authorizedActions.insert(action.id)
                activeReceipt = receipt
                activeActionLabel = fullAction
                pendingAction = nil
                actionDescription = ""
                // Small delay to let the first sheet dismiss before showing receipt
                try await Task.sleep(nanoseconds: 300_000_000)
                showReceipt = true
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}
