//
//  ReceiptView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiptView: View {
    let receipt: Receipt
    let actionText: String
    var referenceID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var recipient = ""
    @State private var sent = false
    @State private var qrImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // QR Code
                if let qr = qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                }

                // Action text
                Text(actionText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Details
                VStack(spacing: 12) {
                    detailRow(label: "Timestamp", value: formattedDate)
                    detailRow(label: "Device ID", value: String(receipt.commitment.deviceID.prefix(8)) + "...")
                    detailRow(label: "Biometric", value: "Face ID")
                    detailRow(label: "Session", value: String(receipt.commitment.sessionNonce.prefix(8)) + "...")
                    if let refID = referenceID, !refID.isEmpty {
                        detailRow(label: "Reference", value: refID)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                // Send To
                VStack(spacing: 12) {
                    Text("Send receipt to:")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        TextField("Email or phone number", text: $recipient)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button(action: { sendReceipt() }) {
                            Image(systemName: sent ? "checkmark.circle.fill" : "paperplane.fill")
                                .foregroundColor(sent ? .green : .white)
                                .padding(10)
                                .background(recipient.isEmpty ? Color.gray : Color.blue)
                                .cornerRadius(8)
                        }
                        .disabled(recipient.isEmpty)
                    }

                    if sent {
                        Text("Receipt shared")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal)

                // Buttons — Share sends QR image, Copy copies receipt data
                HStack(spacing: 16) {
                    if let qr = qrImage {
                        ShareLink(item: Image(uiImage: qr), preview: SharePreview("Trust Mesh Receipt", image: Image(uiImage: qr))) {
                            Label("Share QR", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    Button(action: {
                        UIPasteboard.general.string = receiptData
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }) {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(copied ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Button("Done") {
                    ReceiptStore.shared.save(
                        receipt: receipt,
                        actionText: actionText,
                        recipient: sent ? recipient : nil,
                        referenceID: referenceID
                    )
                    dismiss()
                }
                .foregroundColor(.gray)
                .padding(.top)
            }
            .padding(.vertical, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            qrImage = generateQRCode()
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Send

    private func sendReceipt() {
        UIPasteboard.general.string = receiptData
        sent = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Helpers

    private var receiptData: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(receipt),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(receipt.commitment.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
                .fontDesign(.monospaced)
        }
    }

    private func generateQRCode() -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(receiptData.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let scale = 250.0 / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
