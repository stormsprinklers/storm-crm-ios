import SwiftUI

struct CompanyAccountDTO: Decodable, Identifiable {
    let userId: String
    let companyId: String
    let companyName: String
    let companyLogoUrl: String?
    let name: String
    let role: String
    var id: String { userId }
}

struct CompanyAccountsResponse: Decodable {
    let current: CompanyAccountDTO
    let switchable: [CompanyAccountDTO]
}

struct CompanySwitcherView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var accounts: CompanyAccountsResponse?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if loading { ProgressView("Loading companies…") }
            if let accounts {
                Section("Current company") {
                    HStack { CompanyMenuLogo(account: accounts.current); Text(accounts.current.companyName); Spacer(); Image(systemName: "checkmark.circle.fill") }
                }
                Section("Switch company") {
                    let available = accounts.switchable.filter {
                        ["ADMIN", "MANAGER", "CSR", "SALES", "TECH", "INSTALLER"].contains($0.role)
                        && $0.companyId != accounts.current.companyId
                    }
                    if available.isEmpty { Text("No other linked company accounts.").foregroundStyle(.secondary) }
                    ForEach(available) { account in
                        Button {
                            Task {
                                do { try await env.switchCompany(userId: account.userId) }
                                catch {
                                    let message = (error as? APIError)?.message ?? error.localizedDescription
                                    self.error = message
                                    env.auth.companySwitchError = message
                                }
                            }
                        } label: {
                            HStack {
                            CompanyMenuLogo(account: account)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.companyName)
                                Text("\(account.name) · \(account.role)").font(.caption).foregroundStyle(.secondary)
                            }
                            }
                        }
                    }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Refresh") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Companies")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do { accounts = try await env.apiClient.get(path: APIPath.accountCompanies) }
        catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}

private struct CompanyMenuLogo: View {
    let account: CompanyAccountDTO
    var body: some View {
        AsyncImage(url: account.companyLogoUrl.flatMap { URL(string: $0, relativeTo: URL(string: AppConfig.apiBaseURL)) }) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(String(account.companyName.prefix(1))).font(.headline)
        }.frame(width: 36, height: 36).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
