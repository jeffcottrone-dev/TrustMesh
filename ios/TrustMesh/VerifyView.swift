//
//  VerifyView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

struct VerifyView: View {
    @State private var mode: VerifyMode = .choose
    @State private var pastedJSON = ""
    @State private var result: VerificationResult?
    @State private var isVerifying = false

    enum VerifyMode {
        case choose, scan, paste, result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                Group {
                    switch mode {
                    case .choose: chooseView
                    case .scan: scanView
                    case .paste: pasteView
                    case .result: resultView
                    }
                }
            }
            .navigationTitle("Verify Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .navyTheme()
        }
    }

    // MARK: - Choose mode

    private var chooseView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.shield")
                .font(.system(size: 60))
                .foregroundColor(.tmBlue)

            Text("Verify a Receipt")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Scan a QR code or paste receipt data to verify its authenticity")
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
                    Label("Paste Receipt Data", systemImage: "doc.on.clipboard")
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
                verify(json: scannedString)
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

            HStack(spacing: 16) {
                Button("Back") { mode = .choose }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Button { verify(json: pastedJSON) } label: {
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

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()

            resultContent

            Spacer()

            Button("Verify Another") {
                result = nil
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
    }

    @ViewBuilder
    private var resultContent: some View {
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

        case .none:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func verify(json: String) {
        isVerifying = true
        Task {
            result = await VerificationService.shared.verifyReceipt(json: json)
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
