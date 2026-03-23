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
    @State private var showTransparencyLog = false

    enum VerifyMode {
        case choose, scan, paste, result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Type", selection: $verifyType) {
                        ForEach(VerifyType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: verifyType) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTransparencyLog = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.tmBlue)
                    }
                }
            }
            .sheet(isPresented: $showTransparencyLog) {
                TransparencyLogView()
            }
            .onChange(of: deepLink.pendingVerifyMessageId) {
                if let messageId = deepLink.pendingVerifyMessageId {
                    deepLink.pendingVerifyMessageId = nil
                    verifyType = .message
                    verifyMessageById(messageId)
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
                 : "Scan the QR code from an email or text to verify it's authentic")
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
                    Label(verifyType == .receipt ? "Paste Receipt Data" : "Paste Verification URL",
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
                    // QR contains verification URL or deep link — verify immediately
                    verifyMessageFromInput(scannedString)
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
            if verifyType == .message {
                Text("Paste the verification URL from the message")
                    .font(.caption)
                    .foregroundColor(.tmSilver)
                    .padding(.horizontal)
            }

            TextEditor(text: $pastedJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tmSilver, lineWidth: 1))
                .padding(.horizontal)

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
                        verifyMessageFromInput(pastedJSON)
                    }
                } label: {
                    Group {
                        if isVerifying { ProgressView().tint(.white) } else { Text("Verify") }
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
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                switch messageResult {
                case .valid(let sender, let channel, let timestamp, let message, let organization):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("VERIFIED")
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .foregroundColor(.green)

                    VStack(spacing: 16) {
                        // Organization badge
                        if let org = organization {
                            HStack(spacing: 10) {
                                Image(systemName: org.verified ? "checkmark.shield.fill" : "shield.fill")
                                    .font(.title2)
                                    .foregroundColor(org.verified ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(org.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    HStack(spacing: 4) {
                                        Text(org.verified ? "Verified Organization" : "Unverified Organization")
                                            .font(.caption)
                                            .foregroundColor(org.verified ? .green : .orange)
                                        if let domain = org.domain {
                                            Text("· \(domain)")
                                                .font(.caption)
                                                .foregroundColor(.tmSilver)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                            .background((org.verified ? Color.green : Color.orange).opacity(0.12))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Sender + channel
                        HStack {
                            let ch = MessageChannel(rawValue: channel) ?? .other
                            Image(systemName: ch.icon)
                                .foregroundColor(.tmBlue)
                            Text("via \(ch.label)")
                                .font(.caption)
                                .foregroundColor(.tmBlue)
                            Spacer()
                            Text("From: \(sender)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)

                        // Original signed message
                        if let msg = message, !msg.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Original Signed Message")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.tmSilver)

                                Text(msg)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }

                        Text(formatDate(timestamp))
                            .font(.caption)
                            .foregroundColor(.tmSilver)
                    }

                case .invalid(let reason):
                    invalidView(reason: reason)

                case .none:
                    if isVerifying {
                        Spacer(minLength: 60)
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

                Spacer(minLength: 20)
                if !isVerifying {
                    verifyAnotherButton
                }
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

    private func verifyMessageFromInput(_ input: String) {
        isVerifying = true
        mode = .result
        Task {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("http") {
                // URL — extract message ID and verify
                messageResult = await VerificationService.shared.verifyMessageByURL(url: trimmed)
            } else if trimmed.hasPrefix("trustmesh://verify/") {
                // Deep link
                let messageId = String(trimmed.dropFirst("trustmesh://verify/".count))
                messageResult = await VerificationService.shared.verifyMessageById(messageId)
            } else {
                messageResult = .invalid(reason: "Unrecognized QR code. Expected a TrustMesh verification link.")
            }

            isVerifying = false
        }
    }

    private func verifyMessageById(_ messageId: String) {
        isVerifying = true
        verifyType = .message
        mode = .result
        Task {
            messageResult = await VerificationService.shared.verifyMessageById(messageId)
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
