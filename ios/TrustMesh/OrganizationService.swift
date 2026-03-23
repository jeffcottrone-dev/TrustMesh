//
//  OrganizationService.swift
//  TrustMesh
//

import Foundation

final class OrganizationService {
    static let shared = OrganizationService()

    private let backendURL = "https://trustmesh-production.up.railway.app"

    private init() {}

    // MARK: - Create Organization

    func createOrg(name: String, domain: String?) async throws -> Organization {
        let keyManager = KeyManager.shared
        let deviceID = keyManager.deviceID()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // Build the data to sign
        let signPayload: [String: Any] = [
            "name": name,
            "domain": domain as Any,
            "deviceID": deviceID,
            "timestamp": timestamp,
        ]
        let signData = try JSONSerialization.data(withJSONObject: signPayload, options: .sortedKeys)
        let signatureData = try await keyManager.sign(data: signData)

        let url = URL(string: "\(backendURL)/orgs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": name,
            "deviceID": deviceID,
            "signature": signatureData.base64EncodedString(),
            "timestamp": timestamp,
        ]
        if let domain = domain, !domain.isEmpty {
            body["domain"] = domain
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let respBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw OrgError.serverError(respBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Organization(
            orgID: json?["orgID"] as? String ?? "",
            name: json?["name"] as? String ?? name,
            domain: json?["domain"] as? String,
            verified: false,
            status: json?["status"] as? String ?? "pending",
            role: "admin",
            memberCount: 1
        )
    }

    // MARK: - Get Organization

    func getOrg(_ orgID: String) async -> Organization? {
        guard let url = URL(string: "\(backendURL)/orgs/\(orgID)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Organization.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - My Organizations

    func myOrgs() async -> [Organization] {
        let deviceID = KeyManager.shared.deviceID()
        guard !deviceID.isEmpty,
              let url = URL(string: "\(backendURL)/orgs?deviceID=\(deviceID)") else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([Organization].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Add Member

    func addMember(orgID: String, memberDeviceID: String) async throws {
        let keyManager = KeyManager.shared
        let deviceID = keyManager.deviceID()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        let signPayload: [String: Any] = [
            "orgID": orgID,
            "memberDeviceID": memberDeviceID,
            "deviceID": deviceID,
            "timestamp": timestamp,
        ]
        let signData = try JSONSerialization.data(withJSONObject: signPayload, options: .sortedKeys)
        let signatureData = try await keyManager.sign(data: signData)

        let url = URL(string: "\(backendURL)/orgs/\(orgID)/members")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "deviceID": deviceID,
            "memberDeviceID": memberDeviceID,
            "signature": signatureData.base64EncodedString(),
            "timestamp": timestamp,
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            let respBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw OrgError.serverError(respBody)
        }
    }

    // MARK: - Remove Member

    func removeMember(orgID: String, memberDeviceID: String) async throws {
        let deviceID = KeyManager.shared.deviceID()
        guard let url = URL(string: "\(backendURL)/orgs/\(orgID)/members/\(memberDeviceID)?deviceID=\(deviceID)") else {
            throw OrgError.serverError("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let respBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw OrgError.serverError(respBody)
        }
    }

    // MARK: - List Members

    func listMembers(orgID: String) async -> [OrgMember] {
        let deviceID = KeyManager.shared.deviceID()
        guard let url = URL(string: "\(backendURL)/orgs/\(orgID)/members?deviceID=\(deviceID)") else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([OrgMember].self, from: data)
        } catch {
            return []
        }
    }
}

enum OrgError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let detail):
            return "Organization error: \(detail)"
        }
    }
}
