//
//  ReceiptView.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import MessageUI

struct ReceiptView: View {
    let receipt: Receipt
    let actionText: String
    var referenceID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var recipient = ""
    @State private var sent = false
    @State private var qrImage: UIImage?
    @State private var showMailComposer = false
    @State private var showMessageComposer = false
    @State private var sendError = ""

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
                        Text("Receipt sent!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if !sendError.isEmpty {
                        Text(sendError)
                            .font(.caption)
                            .foregroundColor(.red)
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
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipient: recipient,
                subject: "TrustMesh Authorization Receipt",
                body: "Here is your TrustMesh authorization receipt for: \(actionText)\n\nScan the attached QR code in the TrustMesh app to verify this receipt.\n\nReceipt data:\n\(receiptData)",
                qrImage: qrImage
            ) { result in
                if result == .sent {
                    sent = true
                }
            }
        }
        .sheet(isPresented: $showMessageComposer) {
            MessageComposeView(
                recipient: recipient,
                body: "TrustMesh receipt for: \(actionText) — Scan the QR code in TrustMesh to verify.",
                qrImage: qrImage
            ) { result in
                if result == .sent {
                    sent = true
                }
            }
        }
    }

    // MARK: - Send

    private func sendReceipt() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sendError = ""

        if isPhoneNumber(recipient) {
            if MFMessageComposeViewController.canSendText() {
                showMessageComposer = true
            } else {
                sendError = "Text messaging is not available on this device"
            }
        } else {
            if MFMailComposeViewController.canSendMail() {
                showMailComposer = true
            } else {
                sendError = "Email is not configured on this device"
            }
        }
    }

    private func isPhoneNumber(_ input: String) -> Bool {
        let digits = input.filter { $0.isNumber }
        return digits.count >= 7 && !input.contains("@")
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

// MARK: - Mail Compose View (UIKit wrapper)

struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let qrImage: UIImage?
    let onComplete: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let image = qrImage, let png = image.pngData() {
            vc.addAttachmentData(png, mimeType: "image/png", fileName: "TrustMesh_Receipt.png")
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onComplete: (MFMailComposeResult) -> Void
        init(onComplete: @escaping (MFMailComposeResult) -> Void) {
            self.onComplete = onComplete
        }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onComplete(result)
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Message Compose View (UIKit wrapper)

struct MessageComposeView: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let qrImage: UIImage?
    let onComplete: (MessageComposeResult) -> Void

    enum MessageComposeResult {
        case sent, cancelled, failed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = [recipient]
        vc.body = body
        if let image = qrImage, let png = image.pngData() {
            vc.addAttachmentData(png, typeIdentifier: "public.png", filename: "TrustMesh_Receipt.png")
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onComplete: (MessageComposeResult) -> Void
        init(onComplete: @escaping (MessageComposeResult) -> Void) {
            self.onComplete = onComplete
        }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            let mapped: MessageComposeView.MessageComposeResult
            switch result {
            case .sent: mapped = .sent
            case .cancelled: mapped = .cancelled
            case .failed: mapped = .failed
            @unknown default: mapped = .failed
            }
            onComplete(mapped)
            controller.dismiss(animated: true)
        }
    }
}
