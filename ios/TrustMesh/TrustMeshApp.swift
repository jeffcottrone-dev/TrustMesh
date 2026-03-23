//
//  TrustMeshApp.swift
//  TrustMesh
//
//  Created by Jeff Cottrone on 3/16/26.
//

import SwiftUI

@main
struct TrustMeshApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await ReceiptGenerator.shared.registerDeviceIfNeeded()
                }
                .onOpenURL { url in
                    guard url.scheme == "trustmesh" else { return }

                    if url.host == "session",
                       let code = url.pathComponents.last,
                       code.count == 6 {
                        // Handle trustmesh://session/{code}
                        DeepLinkManager.shared.pendingSessionCode = code
                    } else if url.host == "verify",
                              let messageId = url.pathComponents.last,
                              !messageId.isEmpty {
                        // Handle trustmesh://verify/{messageId}
                        DeepLinkManager.shared.pendingVerifyMessageId = messageId
                    }
                }
        }
    }
}
