//
//  OrganizationModels.swift
//  TrustMesh
//

import Foundation

struct Organization: Codable, Identifiable {
    var id: String { orgID }
    let orgID: String
    let name: String
    let domain: String?
    let verified: Bool
    let status: String
    let role: String?
    let memberCount: Int?
}

struct OrgMember: Codable, Identifiable {
    var id: String { deviceID }
    let deviceID: String
    let displayName: String?
    let role: String
    let joinedAt: String
}

struct VerifiedOrg {
    let name: String
    let verified: Bool
    let domain: String?
}
