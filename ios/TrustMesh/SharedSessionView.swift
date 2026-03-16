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

    enum SessionMode {
        case choose, create, join, ready
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
                Button(action: { createSession() }) {
                    Label("Create Session", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: { mode = .join }) {
                    Label("Join Session", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)

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

            HStack(spacing: 16) {
                Button("Back") { mode = .choose; sessionCode = "" }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)

                Button(action: { mode = .ready }) {
                    Text("Join")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sessionCode.count >= 6 ? Color.purple : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(sessionCode.count < 6)
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
                mode = .choose
                sessionCode = ""
                actionText = ""
                errorMessage = ""
            }
            .foregroundColor(.gray)
            .padding(.bottom)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Helpers

    private func createSession() {
        let code = String(format: "%06d", Int.random(in: 100000...999999))
        sessionCode = code
        mode = .create
    }

    private func authorize() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fullAction = "[\(sessionCode)] \(actionText)"
                let receipt = try await ReceiptGenerator.shared.generateReceipt(actionText: fullAction)
                currentReceipt = receipt
                showReceipt = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
