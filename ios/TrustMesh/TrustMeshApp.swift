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
        }
    }
}
