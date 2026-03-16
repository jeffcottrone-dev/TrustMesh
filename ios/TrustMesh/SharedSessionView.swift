//
//  SharedSessionView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

struct SharedSessionView: View {
    @State private var mode: SessionMode = .choose
    @State private var sessionCode = ""
    @State private var actionText = ""
    @State private var currentReceipt: Receipt?
    @State private var showReceipt = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var role: String = ""
    @State private var partnerSubmitted = false
    @State private var pollTimer: Timer?

    private let backendURL = "https://trustmesh-production.up.railway.app"

    enum SessionMode {
        case choose, create, join, ready, submitted
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .choose:
                    chooseView
                case .create:
                    createView
                case .join:
                    joinView
                case .ready:
                    readyView
                case .submitted:
                    submittedView
                }
            }
            .navigationTitle("Shared Session")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showReceipt) {
                if let receipt = currentReceipt {
                    ReceiptView(receipt: receipt, actionText: actionText, referenceID: sessionCode)
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }

    // MARK: - Choose

    private var chooseView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.circle")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Shared Session")
                .font(.title2)
                .fontWeight(.bold)

            Text("Both parties enter the same session code, then each authorizes their side. Receipts are linked together as proof.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Button(action: { createSessionOnServer() }) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Label("Create Session", systemImage: "plus.circle")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading)

                Button(action: { mode = .join }) {
                    Label("Join Session", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(10)
                }
                .disabled(isLoading)
            }
            .padding(.horizontal)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Create

    private var createView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "number.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.purple)

            Text("Your Session Code")
                .font(.headline)

            Text(sessionCode)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.purple)
                .kerning(8)

            Text("Share this code with the other party")
                .font(.subheadline)
                .foregroundColor(.gray)

            Button(action: {
                UIPasteboard.general.string = sessionCode
            }) {
                Label("Copy Code", systemImage: "doc.on.doc")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
            }

            Button(action: { mode = .ready }) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Join

    private var joinView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 50))
                .foregroundColor(.purple)

            Text("Enter Session Code")
                .font(.headline)

            TextField("6-digit code", text: $sessionCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(width: 200)
                .textFieldStyle(.roundedBorder)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button("Back") { mode = .choose; sessionCode = ""; errorMessage = "" }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)

                Button(action: { joinSessionOnServer() }) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Join")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(sessionCode.count >= 6 ? Color.purple : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(sessionCode.count < 6 || isLoading)
            }
            .padding(.horizontal)

            Spacer()
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Ready to authorize

    private var readyView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Session: \(sessionCode)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.purple)
                Text("Role: \(role == "creator" ? "Creator" : "Joiner")")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top)

            TextField("Describe your side of the agreement...", text: $actionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .padding(.horizontal)

            Button(action: { authorize() }) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("Authorize with Face ID", systemImage: "faceid")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(actionText.isEmpty ? Color.gray : Color.purple)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
            .disabled(actionText.isEmpty || isLoading)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            Button("Start Over") {
                resetState()
            }
            .foregroundColor(.gray)
            .padding(.bottom)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Submitted — waiting for partner

    private var submittedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: partnerSubmitted ? "checkmark.circle.fill" : "hourglass")
                .font(.system(size: 60))
                .foregroundColor(partnerSubmitted ? .green : .purple)

            Text(partnerSubmitted ? "Session Complete" : "Waiting for Partner")
                .font(.title2)
                .fontWeight(.bold)

            Text("Session: \(sessionCode)")
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.purple)

            if partnerSubmitted {
                Text("Both parties have submitted their authorization receipts. The session is complete.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: {
                    showReceipt = true
                }) {
                    Label("View Your Receipt", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            } else {
                Text("Your receipt has been submitted. Waiting for the other party to authorize their side...")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ProgressView()
                    .tint(.purple)
            }

            Spacer()

            Button("Start Over") {
                resetState()
            }
            .foregroundColor(.gray)
            .padding(.bottom)
        }
    }

    // MARK: - Server Actions

    private func createSessionOnServer() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let deviceID = KeyManager.shared.deviceID()
                let url = URL(string: "\(backendURL)/sessions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["deviceID": deviceID])

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                    let body = String(data: data, encoding: .utf8) ?? "unknown error"
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: body])
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                sessionCode = json?["code"] as? String ?? ""
                role = "creator"
                mode = .create
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func joinSessionOnServer() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let deviceID = KeyManager.shared.deviceID()
                let url = URL(string: "\(backendURL)/sessions/\(sessionCode)/join")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["deviceID": deviceID])

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "unknown error"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? String {
                        throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: error])
                    }
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: body])
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                role = json?["role"] as? String ?? "joiner"
                mode = .ready
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func authorize() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fullAction = "[\(sessionCode)] \(actionText)"
                let receipt = try await ReceiptGenerator.shared.generateReceipt(actionText: fullAction)
                currentReceipt = receipt

                // Save to local history immediately
                ReceiptStore.shared.save(
                    receipt: receipt,
                    actionText: fullAction,
                    referenceID: sessionCode
                )

                // Submit receipt to backend
                try await submitReceiptToServer(receipt: receipt)

                mode = .submitted
                startPollingForPartner()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func submitReceiptToServer(receipt: Receipt) async throws {
        let deviceID = KeyManager.shared.deviceID()
        let url = URL(string: "\(backendURL)/sessions/\(sessionCode)/receipt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let receiptData = try encoder.encode(receipt)
        let receiptJSON = try JSONSerialization.jsonObject(with: receiptData)

        let body: [String: Any] = [
            "deviceID": deviceID,
            "receipt": receiptJSON
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: body])
        }

        // Check if partner already submitted
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if json?["status"] as? String == "complete" {
            await MainActor.run {
                partnerSubmitted = true
            }
        }
    }

    private func startPollingForPartner() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await checkSessionStatus()
            }
        }
    }

    private func checkSessionStatus() async {
        guard let url = URL(string: "\(backendURL)/sessions/\(sessionCode)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if json?["status"] as? String == "complete" {
                await MainActor.run {
                    partnerSubmitted = true
                    pollTimer?.invalidate()
                }
            }
        } catch {
            print("Session poll error: \(error)")
        }
    }

    // MARK: - Helpers

    private func resetState() {
        pollTimer?.invalidate()
        mode = .choose
        sessionCode = ""
        actionText = ""
        errorMessage = ""
        role = ""
        partnerSubmitted = false
        currentReceipt = nil
    }
}
