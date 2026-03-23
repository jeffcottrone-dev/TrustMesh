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
    var deepLink = DeepLinkManager.shared
    @State private var isProcessingDeepLink = false
    @State private var deepLinkReceipt: Receipt?
    @State private var deepLinkActionText = ""
    @State private var deepLinkSessionCode = ""

    private let backendURL = "https://trustmesh-production.up.railway.app"

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
        .onChange(of: deepLink.pendingSessionCode) {
            if let code = deepLink.pendingSessionCode {
                deepLink.pendingSessionCode = nil
                deepLinkReceipt = nil
                deepLinkSessionCode = code
                isProcessingDeepLink = true
                Task { await handleDeepLink(code: code) }
            }
        }
        .fullScreenCover(isPresented: $isProcessingDeepLink, onDismiss: {
            deepLinkReceipt = nil
            deepLinkActionText = ""
            deepLinkSessionCode = ""
        }) {
            if let receipt = deepLinkReceipt {
                ReceiptView(receipt: receipt, actionText: deepLinkActionText, referenceID: deepLinkSessionCode)
            } else {
                ZStack {
                    Color.tmNavy.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.tmBlue)
                            .scaleEffect(1.5)
                        Text("Authorizing...")
                            .font(.headline)
                            .foregroundColor(.tmBlue)
                    }
                }
            }
        }
    }

    private func handleDeepLink(code: String) async {
        do {
            // 1. Join session silently to get action text
            let deviceID = KeyManager.shared.deviceID()
            let joinURL = URL(string: "\(backendURL)/sessions/\(code)/join")!
            var joinRequest = URLRequest(url: joinURL)
            joinRequest.httpMethod = "POST"
            joinRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            joinRequest.httpBody = try JSONSerialization.data(withJSONObject: ["deviceID": deviceID])

            let (joinData, _) = try await URLSession.shared.data(for: joinRequest)
            let joinJSON = try JSONSerialization.jsonObject(with: joinData) as? [String: Any]
            let actionText = joinJSON?["actionText"] as? String ?? "Authorization requested"

            // 2. Face ID + generate receipt
            let fullAction = "[\(code)] \(actionText)"
            let receipt = try await ReceiptGenerator.shared.generateReceipt(actionText: fullAction)

            // 3. Save to local history
            ReceiptStore.shared.save(receipt: receipt, actionText: fullAction, referenceID: code)

            // 4. Submit receipt to server (so Chase PWA detects it)
            let receiptURL = URL(string: "\(backendURL)/sessions/\(code)/receipt")!
            var receiptRequest = URLRequest(url: receiptURL)
            receiptRequest.httpMethod = "POST"
            receiptRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let receiptData = try encoder.encode(receipt)
            let receiptJSON = try JSONSerialization.jsonObject(with: receiptData)
            receiptRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "deviceID": deviceID,
                "receipt": receiptJSON
            ])
            _ = try await URLSession.shared.data(for: receiptRequest)

            // 5. Show receipt (fullScreenCover transitions from loading → receipt)
            deepLinkReceipt = receipt
            deepLinkActionText = actionText
        } catch {
            print("Deep link auth error: \(error)")
            isProcessingDeepLink = false
        }
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

enum AuthMode: String, CaseIterable {
    case receipt = "Receipt"
    case message = "Message"
}

struct AuthorizeView: View {
    @State private var authMode: AuthMode = .receipt

    // Receipt mode state
    @State private var actionText = "Selling couch to Brian Walker — $400 Venmo"
    @State private var statusMessage = ""
    @State private var isLoading = false
    @State private var currentReceipt: Receipt?
    @State private var currentActionText = ""
    @State private var showReceipt = false

    // Message mode state
    @State private var messageText = ""
    @State private var selectedChannel: MessageChannel = .sms
    @State private var includeMessageText = true
    @State private var currentArtifact: VerifiedMessageArtifact?
    @State private var currentMessageText = ""
    @State private var currentChannel: MessageChannel = .sms
    @State private var showArtifact = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Mode picker
                    Picker("Mode", selection: $authMode) {
                        ForEach(AuthMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    switch authMode {
                    case .receipt:
                        receiptModeView
                    case .message:
                        messageModeView
                    }

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
            .sheet(isPresented: $showArtifact) {
                if let artifact = currentArtifact {
                    MessageArtifactView(artifact: artifact, messageText: currentMessageText, channel: currentChannel)
                }
            }
        }
    }

    // MARK: - Receipt Mode (existing)

    private var receiptModeView: some View {
        VStack(spacing: 20) {
            TMTextField(placeholder: "Describe the Action to Authorize...", text: $actionText)
                .padding(.horizontal)
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }

            authorizeButton
                .padding(.horizontal)
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

    // MARK: - Message Mode (new)

    private var messageModeView: some View {
        VStack(spacing: 20) {
            // Channel picker
            HStack(spacing: 12) {
                ForEach(MessageChannel.allCases, id: \.self) { ch in
                    Button {
                        selectedChannel = ch
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ch.icon)
                                .font(.title3)
                            Text(ch.label)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedChannel == ch ? Color.tmBlue : Color.white.opacity(0.08))
                        .foregroundColor(selectedChannel == ch ? .white : .tmSilver)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)

            // Message text field
            TMTextField(placeholder: "Enter message to sign...", text: $messageText, axis: .vertical)
                .padding(.horizontal)
                .lineLimit(3...6)
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }

            // Include text toggle
            Toggle(isOn: $includeMessageText) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .foregroundColor(.tmSilver)
                    Text("Include message text (verifiers can read it)")
                        .font(.caption)
                        .foregroundColor(.tmSilver)
                }
            }
            .tint(.tmBlue)
            .padding(.horizontal)

            // Sign button
            Button(action: {
                dismissKeyboard()
                signMessage()
            }) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Label("Sign with Face ID", systemImage: "faceid")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(messageText.isEmpty ? Color.tmSilver : Color.tmBlue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(messageText.isEmpty || isLoading)
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

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

    private func signMessage() {
        isLoading = true
        statusMessage = ""
        Task {
            do {
                let artifact = try await MessageGenerator.shared.generateSignedMessage(
                    messageText: messageText,
                    channel: selectedChannel,
                    includeText: includeMessageText
                )
                currentArtifact = artifact
                currentMessageText = messageText
                currentChannel = selectedChannel
                showArtifact = true
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
