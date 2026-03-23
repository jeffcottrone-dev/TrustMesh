//
//  MessageArtifactView.swift
//  TrustMesh
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct MessageArtifactView: View {
    let artifact: VerifiedMessageArtifact
    let messageText: String
    let channel: MessageChannel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var qrImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // QR Code (encodes verification URL)
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

                // Channel badge + message preview
                HStack(spacing: 8) {
                    Image(systemName: channel.icon)
                        .foregroundColor(.tmBlue)
                    Text(channel.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.tmBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.tmBlue.opacity(0.2))
                        .cornerRadius(8)

                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Signed")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal)

                // Message text
                Text(messageText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Details
                VStack(spacing: 12) {
                    detailRow(label: "Timestamp", value: formattedDate)
                    detailRow(label: "Device ID", value: String(artifact.commitment.senderID.prefix(8)) + "...")
                    detailRow(label: "Channel", value: channel.label)
                    detailRow(label: "Message ID", value: String(artifact.messageId.prefix(8)) + "...")
                    if let url = artifact.verificationURL {
                        detailRow(label: "Verify URL", value: String(url.suffix(44)))
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                // Verification URL
                if let url = artifact.verificationURL {
                    VStack(spacing: 8) {
                        Text("Verification Link")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.tmBlue)
                            .fontDesign(.monospaced)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)
                }

                // Buttons
                HStack(spacing: 16) {
                    if let qr = qrImage {
                        ShareLink(item: Image(uiImage: qr), preview: SharePreview("TrustMesh Verified Message", image: Image(uiImage: qr))) {
                            Label("Share QR", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.tmBlue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    Button(action: {
                        if let url = artifact.verificationURL {
                            UIPasteboard.general.string = url
                        } else {
                            UIPasteboard.general.string = artifactJSON
                        }
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }) {
                        Label(copied ? "Copied!" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(copied ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Button("Done") {
                    MessageStore.shared.save(
                        artifact: artifact,
                        messageText: messageText,
                        channel: channel.rawValue
                    )
                    dismiss()
                }
                .foregroundColor(.gray)
                .padding(.top)
            }
            .padding(.vertical, 32)
        }
        .background(Color.tmNavy.ignoresSafeArea())
        .onAppear {
            qrImage = generateQRCode()
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(artifact.commitment.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var artifactJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(artifact),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
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
        // QR encodes the verification URL (simple, works for non-app users)
        guard let urlString = artifact.verificationURL else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(urlString.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let scale = 250.0 / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
