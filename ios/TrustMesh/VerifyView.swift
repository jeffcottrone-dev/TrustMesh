//
//  VerifyView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

enum VerifyType: String, CaseIterable {
    case receipt = "Receipt"
    case message = "Message"
}

struct VerifyView: View {
    @State private var verifyType: VerifyType = .receipt
    @State private var mode: VerifyMode = .choose
    @State private var pastedJSON = ""
    @State private var result: VerificationResult?
    @State private var messageResult: MessageVerificationResult?
    @State private var isVerifying = false

    // Deep link support
    var deepLink = DeepLinkManager.shared

    enum VerifyMode {
        case choose, scan, paste, result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Type picker
                    Picker("Type", selection: $verifyType) {
                        ForEach(VerifyType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: verifyType) {
                        // Reset state when switching
                        mode = .choose
                        result = nil
                        messageResult = nil
                        pastedJSON = ""
                    }

                    Group {
                        switch mode {
                        case .choose: chooseView
                        case .scan: scanView
                        case .paste: pasteView
                        case .result:
                            if verifyType == .receipt {
                                receiptResultView
                            } else {
                                messageResultView
                            }
                        }
                    }
                }
            }
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .navyTheme()
            .onChange(of: deepLink.pendingVerifyMessageId) {
                if let messageId = deepLink.pendingVerifyMessageId {
                    deepLink.pendingVerifyMessageId = nil
                    verifyType = .message
                    isVerifying = true
                    Task {
                        messageResult = await VerificationService.shared.verifyMessageById(messageId)
                        mode = .result
                        isVerifying = false
                    }
                }
            }
        }
    }

    // MARK: - Choose mode

    private var chooseView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: verifyType == .receipt ? "checkmark.shield" : "envelope.badge.shield.half.filled")
                .font(.system(size: 60))
                .foregroundColor(.tmBlue)

            Text(verifyType == .receipt ? "Verify a Receipt" : "Verify a Message")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(verifyType == .receipt
                 ? "Scan a QR code or paste receipt data to verify its authenticity"
                 : "Scan a QR code, paste a URL, or paste message data to verify")
                .font(.subheadline)
                .foregroundColor(.tmSilver)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Button { mode = .scan } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.tmBlue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button { mode = .paste } label: {
                    Label(verifyType == .receipt ? "Paste Receipt Data" : "Paste URL or Data",
                          systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.tmBlue)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - QR Scanner

    private var scanView: some View {
        ZStack {
            QRScannerView { scannedString in
                if verifyType == .receipt {
                    verifyReceipt(json: scannedString)
                } else {
                    verifyMessageInput(scannedString)
                }
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                Button("Cancel") { mode = .choose }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Paste

    private var pasteView: some View {
        VStack(spacing: 16) {
            TextEditor(text: $pastedJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tmSilver, lineWidth: 1))
                .padding(.horizontal)

            if verifyType == .message {
                Text("Paste a verification URL or message artifact JSON")
                    .font(.caption)
                    .foregroundColor(.tmSilver)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button("Back") { mode = .choose }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Button {
                    if verifyType == .receipt {
                        verifyReceipt(json: pastedJSON)
                    } else {
                        verifyMessageInput(pastedJSON)
                    }
                } label: {
                    Group {
                        if isVerifying { ProgressView() } else { Text("Verify") }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(pastedJSON.isEmpty ? Color.tmSilver : Color.tmBlue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(pastedJSON.isEmpty || isVerifying)
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }

    // MARK: - Receipt Result

    private var receiptResultView: some View {
        VStack(spacing: 24) {
            Spacer()

            switch result {
            case .valid(let action, let timestamp, let deviceID):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                Text("VERIFIED")
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundColor(.green)
                VStack(spacing: 12) {
                    Text(action)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(formatDate(timestamp))
                        .font(.subheadline)
                        .foregroundColor(.tmSilver)
                    Text("Device: \(String(deviceID.prefix(8)))...")
                        .font(.caption)
                        .foregroundColor(.tmSilver)
                        .fontDesign(.monospaced)
                }
                .padding(.horizontal)

            case .invalid(let reason):
                invalidView(reason: reason)

            case .none:
                EmptyView()
            }

            Spacer()
            verifyAnotherButton
        }
    }

    // MARK: - Message Result

    private var messageResultView: some View {
        VStack(spacing: 24) {
            Spacer()

            switch messageResult {
            case .valid(let sender, let channel, let timestamp, let message):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                Text("VERIFIED")
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundColor(.green)
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        let ch = MessageChannel(rawValue: channel) ?? .other
                        Image(systemName: ch.icon)
                            .foregroundColor(.tmBlue)
                        Text(ch.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.tmBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.tmBlue.opacity(0.2))
                            .cornerRadius(8)
                    }

                    Text("From: \(sender)")
                        .font(.headline)
                        .foregroundColor(.white)

                    if let msg = message, !msg.isEmpty {
                        Text(msg)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                    }

                    Text(formatDate(timestamp))
                        .font(.subheadline)
                        .foregroundColor(.tmSilver)
                }
                .padding(.horizontal)

            case .invalid(let reason):
                invalidView(reason: reason)

            case .none:
                if isVerifying {
                    ProgressView()
                        .tint(.tmBlue)
                        .scaleEffect(1.5)
                    Text("Verifying...")
                        .font(.headline)
                        .foregroundColor(.tmBlue)
                } else {
                    EmptyView()
                }
            }

            Spacer()
            if !isVerifying {
                verifyAnotherButton
            }
        }
    }

    // MARK: - Shared Views

    private func invalidView(reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            Text("INVALID")
                .font(.largeTitle)
                .fontWeight(.black)
                .foregroundColor(.red)
            Text(reason)
                .font(.subheadline)
                .foregroundColor(.tmSilver)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var verifyAnotherButton: some View {
        Button("Verify Another") {
            result = nil
            messageResult = nil
            pastedJSON = ""
            mode = .choose
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.tmBlue)
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Actions

    private func verifyReceipt(json: String) {
        isVerifying = true
        Task {
            result = await VerificationService.shared.verifyReceipt(json: json)
            mode = .result
            isVerifying = false
        }
    }

    private func verifyMessageInput(_ input: String) {
        isVerifying = true
        Task {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("http") {
                // URL — server-side verify
                messageResult = await VerificationService.shared.verifyMessageByURL(trimmed)
            } else if let data = trimmed.data(using: .utf8),
                      let artifact = try? JSONDecoder().decode(VerifiedMessageArtifact.self, from: data) {
                // JSON artifact — local P-256 verify
                messageResult = await VerificationService.shared.verifyMessage(artifact: artifact)
            } else {
                messageResult = .invalid(reason: "Could not parse input. Paste a verification URL or message artifact JSON.")
            }

            mode = .result
            isVerifying = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
