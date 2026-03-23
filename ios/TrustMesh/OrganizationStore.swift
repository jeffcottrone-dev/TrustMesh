//
//  OrganizationStore.swift
//  TrustMesh
//

import Foundation

@Observable
final class OrganizationStore {
    static let shared = OrganizationStore()

    var orgs: [Organization] = []
    var isLoading = false

    private init() {}

    func refresh() async {
        isLoading = true
        orgs = await OrganizationService.shared.myOrgs()
        isLoading = false
    }
}
