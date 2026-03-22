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
                    // Handle trustmesh://session/{code}
                    guard url.scheme == "trustmesh",
                          url.host == "session",
                          let code = url.pathComponents.last,
                          code.count == 6
                    else { return }
                    DeepLinkManager.shared.pendingSessionCode = code
                }
        }
    }
}
