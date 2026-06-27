import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.user {
                    Section("Account") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.replacingOccurrences(of: "_", with: " "))
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.logout() }
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}
