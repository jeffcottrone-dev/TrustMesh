//
//  OrganizationView.swift
//  TrustMesh
//

import SwiftUI

struct OrganizationView: View {
    var store = OrganizationStore.shared
    @State private var showCreateSheet = false
    @State private var selectedOrg: Organization?
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                if store.isLoading && store.orgs.isEmpty {
                    ProgressView()
                        .tint(.tmBlue)
                        .scaleEffect(1.5)
                } else if store.orgs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "building.2")
                            .font(.system(size: 50))
                            .foregroundColor(.tmSilver)
                        Text("No Organizations")
                            .font(.headline)
                            .foregroundColor(.tmSilver)
                        Text("Create an organization to sign messages with your company identity.")
                            .font(.subheadline)
                            .foregroundColor(.tmSilver)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(store.orgs) { org in
                            Button {
                                selectedOrg = org
                            } label: {
                                orgRow(org)
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                    .scrollContentBackground(.hidden)
                }

                if !statusMessage.isEmpty {
                    VStack {
                        Spacer()
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .padding()
                    }
                }
            }
            .navigationTitle("Organizations")
            .navyTheme()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.tmBlue)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateOrgSheet { org in
                    store.orgs.insert(org, at: 0)
                    statusMessage = "Created \(org.name)"
                    clearStatus()
                }
            }
            .sheet(item: $selectedOrg) { org in
                OrgDetailSheet(org: org)
            }
            .task {
                await store.refresh()
            }
        }
    }

    private func orgRow(_ org: Organization) -> some View {
        HStack(spacing: 12) {
            Image(systemName: org.verified ? "checkmark.shield.fill" : "building.2")
                .font(.title2)
                .foregroundColor(org.verified ? .green : .tmBlue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(org.name)
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    if let domain = org.domain, !domain.isEmpty {
                        Text(domain)
                            .font(.caption)
                            .foregroundColor(.tmSilver)
                    }
                    Text(org.role ?? "member")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.tmBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.tmBlue.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            Spacer()

            if let count = org.memberCount {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.tmSilver)
                Image(systemName: "person.2")
                    .font(.caption)
                    .foregroundColor(.tmSilver)
            }
        }
        .padding(.vertical, 4)
    }

    private func clearStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = ""
        }
    }
}

// MARK: - Create Organization Sheet

struct CreateOrgSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var domain = ""
    @State private var isCreating = false
    @State private var error = ""

    let onCreated: (Organization) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.tmBlue)
                        .padding(.top, 20)

                    TMTextField(placeholder: "Organization Name", text: $name)
                        .padding(.horizontal)

                    TMTextField(placeholder: "Domain (optional, e.g. company.com)", text: $domain)
                        .padding(.horizontal)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    if !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Button {
                        createOrg()
                    } label: {
                        Group {
                            if isCreating {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create with Face ID", systemImage: "faceid")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.isEmpty ? Color.tmSilver : Color.tmBlue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(name.isEmpty || isCreating)
                    .padding(.horizontal)

                    Text("Creating an organization requires Face ID to sign the request with your device key.")
                        .font(.caption)
                        .foregroundColor(.tmSilver)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    Spacer()
                }
            }
            .navigationTitle("New Organization")
            .navigationBarTitleDisplayMode(.inline)
            .navyTheme()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.tmBlue)
                }
            }
        }
    }

    private func createOrg() {
        isCreating = true
        error = ""
        Task {
            do {
                let org = try await OrganizationService.shared.createOrg(
                    name: name,
                    domain: domain.isEmpty ? nil : domain
                )
                onCreated(org)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Organization Detail Sheet

struct OrgDetailSheet: View {
    let org: Organization
    @Environment(\.dismiss) private var dismiss
    @State private var members: [OrgMember] = []
    @State private var newMemberID = ""
    @State private var isLoading = true
    @State private var statusMessage = ""

    private var isAdmin: Bool { org.role == "admin" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tmNavy.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Org header
                        VStack(spacing: 8) {
                            Image(systemName: org.verified ? "checkmark.shield.fill" : "building.2")
                                .font(.system(size: 50))
                                .foregroundColor(org.verified ? .green : .tmBlue)

                            Text(org.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            if let domain = org.domain, !domain.isEmpty {
                                Text(domain)
                                    .font(.subheadline)
                                    .foregroundColor(.tmSilver)
                            }

                            HStack(spacing: 8) {
                                Text(org.verified ? "Verified" : "Unverified")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(org.verified ? .green : .orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background((org.verified ? Color.green : Color.orange).opacity(0.2))
                                    .cornerRadius(8)

                                Text(org.status)
                                    .font(.caption)
                                    .foregroundColor(.tmSilver)
                            }
                        }
                        .padding(.top, 20)

                        // Domain verification instructions
                        if isAdmin && !org.verified, let domain = org.domain, !domain.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Domain Verification")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Add a DNS TXT record to \(domain):")
                                    .font(.caption)
                                    .foregroundColor(.tmSilver)
                                Text("trustmesh-verify=\(org.orgID)")
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.tmBlue)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(6)
                            }
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }

                        // Members section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Members (\(members.count))")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            if isLoading {
                                ProgressView().tint(.tmBlue).padding()
                            } else {
                                ForEach(members) { member in
                                    memberRow(member)
                                }
                            }

                            // Add member (admin only)
                            if isAdmin {
                                VStack(spacing: 8) {
                                    TMTextField(placeholder: "Member Device ID", text: $newMemberID)
                                    Button {
                                        addMember()
                                    } label: {
                                        Label("Add Member", systemImage: "person.badge.plus")
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(newMemberID.isEmpty ? Color.tmSilver : Color.tmBlue)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    .disabled(newMemberID.isEmpty)
                                }
                                .padding(.horizontal)
                            }
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle(org.name)
            .navigationBarTitleDisplayMode(.inline)
            .navyTheme()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.tmBlue)
                }
            }
            .task {
                members = await OrganizationService.shared.listMembers(orgID: org.orgID)
                isLoading = false
            }
        }
    }

    private func memberRow(_ member: OrgMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: member.role == "admin" ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.title3)
                .foregroundColor(member.role == "admin" ? .green : .tmBlue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName ?? "Device \(String(member.deviceID.prefix(8)))...")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(member.role)
                    .font(.caption2)
                    .foregroundColor(.tmSilver)
            }

            Spacer()

            if isAdmin && member.role != "admin" {
                Button {
                    removeMember(member.deviceID)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func addMember() {
        let memberID = newMemberID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !memberID.isEmpty else { return }
        Task {
            do {
                try await OrganizationService.shared.addMember(orgID: org.orgID, memberDeviceID: memberID)
                members = await OrganizationService.shared.listMembers(orgID: org.orgID)
                newMemberID = ""
                statusMessage = "Member added"
                clearStatus()
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
                clearStatus()
            }
        }
    }

    private func removeMember(_ deviceID: String) {
        Task {
            do {
                try await OrganizationService.shared.removeMember(orgID: org.orgID, memberDeviceID: deviceID)
                members = await OrganizationService.shared.listMembers(orgID: org.orgID)
                statusMessage = "Member removed"
                clearStatus()
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
                clearStatus()
            }
        }
    }

    private func clearStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = ""
        }
    }
}
