//
//  DeepLinkManager.swift
//  TrustMesh
//

import SwiftUI

@Observable
class DeepLinkManager {
    static let shared = DeepLinkManager()
    var pendingSessionCode: String?
    private init() {}
}
