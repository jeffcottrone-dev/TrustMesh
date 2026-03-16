//
//  ContentView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ProtectedAppsView()
                .tabItem {
                    Label("Apps", systemImage: "lock.shield")
                }

            AuthorizeView()
                .tabItem {
                    Label("Authorize", systemImage: "signature")
                }

            SharedSessionView()
                .tabItem {
                    Label("Session", systemImage: "person.2")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            VerifyView()
                .tabItem {
                    Label("Verify", systemImage: "checkmark.shield")
                }
        }
    }
}

// MARK: - Authorize Tab (receipt generator)

struct AuthorizeView: View {
    @State private var actionText = ""
    @State private var statusMessage = ""
    @State private var isLoading = false
    @State private var currentReceipt: Receipt?
    @State private var currentActionText = ""
    @State private var showReceipt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Describe the action to authorize...", text: $actionText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .submitLabel(.done)
                    .onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    generateReceipt()
                }) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Generate Receipt", systemImage: "faceid")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(actionText.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(actionText.isEmpty || isLoading)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Authorize")
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .sheet(isPresented: $showReceipt) {
                if let receipt = currentReceipt {
                    ReceiptView(receipt: receipt, actionText: currentActionText)
                }
            }
        }
    }

    private func generateReceipt() {
        isLoading = true
        statusMessage = ""

        Task {
            do {
                let receipt = try await ReceiptGenerator.shared.generateReceipt(actionText: actionText)
                currentReceipt = receipt
                currentActionText = actionText
                showReceipt = true
                statusMessage = ""
            } catch {
                print("Error: \(error)")
                statusMessage = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
