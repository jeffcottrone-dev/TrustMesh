//
//  ContentView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let tmBlue = Color(red: 0.29, green: 0.50, blue: 0.76)
    static let tmNavy = Color(red: 0.11, green: 0.16, blue: 0.29)
    static let tmSilver = Color(red: 0.75, green: 0.78, blue: 0.82)
}

// MARK: - Navy background modifier

struct NavyBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.tmNavy.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.tmNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func navyTheme() -> some View {
        modifier(NavyBackground())
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ProtectedAppsView()
                .tabItem { Label("Apps", systemImage: "lock.shield") }
            AuthorizeView()
                .tabItem { Label("Authorize", systemImage: "signature") }
            SharedSessionView()
                .tabItem { Label("Session", systemImage: "person.2") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            VerifyView()
                .tabItem { Label("Verify", systemImage: "checkmark.shield") }
        }
        .tint(.tmBlue)
    }
}

// MARK: - Styled text field

struct TMTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .padding(12)
            .foregroundColor(.white)
            .background(Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tmSilver, lineWidth: 1))
            .cornerRadius(8)
    }
}

// MARK: - Authorize Tab

struct AuthorizeView: View {
    @State private var actionText = ""
    @State private var statusMessage = ""
    @State private var isLoading = false
    @State private var currentReceipt: Receipt?
    @State private var currentActionText = ""
    @State private var showReceipt = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 20) {
                    TMTextField(placeholder: "Describe the Action to Authorize...", text: $actionText)
                        .padding(.horizontal)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }

                    authorizeButton
                        .padding(.horizontal)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Authorize")
            .navyTheme()
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .sheet(isPresented: $showReceipt) {
                if let receipt = currentReceipt {
                    ReceiptView(receipt: receipt, actionText: currentActionText)
                }
            }
        }
    }

    private var authorizeButton: some View {
        Button(action: {
            dismissKeyboard()
            generateReceipt()
        }) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Label("Authorize with Face ID", systemImage: "faceid")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(actionText.isEmpty ? Color.tmSilver : Color.tmBlue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(actionText.isEmpty || isLoading)
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
                statusMessage = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ContentView()
}
