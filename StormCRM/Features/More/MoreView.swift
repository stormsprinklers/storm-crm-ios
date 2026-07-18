import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var offlineSync: OfflineSyncManager

    @State private var showSignOutConfirm = false
    @State private var showPendingSyncAlert = false

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

                Section("Tools") {
                    NavigationLink {
                        SyncStatusView()
                    } label: {
                        HStack {
                            Label("Sync status", systemImage: "arrow.triangle.2.circlepath.icloud")
                            Spacer()
                            if offlineSync.pendingCount > 0 {
                                Text("\(offlineSync.pendingCount)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(StormTheme.coral.opacity(0.15))
                                    .foregroundStyle(StormTheme.coral)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    NavigationLink {
                        TimeClockView()
                    } label: {
                        Label("Timesheets", systemImage: "clock")
                    }

                    if let role = auth.user?.role, UserRoles.canViewReporting(role) {
                        NavigationLink {
                            ReportDetailView(kind: .kpiDashboard)
                        } label: {
                            Label("Reports", systemImage: "chart.bar")
                        }
                    }

                    NavigationLink {
                        MissedTransfersView()
                    } label: {
                        Label("Missed transfers", systemImage: "phone.arrow.down.left")
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        if offlineSync.pendingCount > 0 {
                            showPendingSyncAlert = true
                        } else {
                            showSignOutConfirm = true
                        }
                    }
                }
            }
            .navigationTitle("More")
            .alert("Pending sync", isPresented: $showPendingSyncAlert) {
                Button("Sync now") {
                    offlineSync.flushOutbox()
                }
                Button("Sign out anyway", role: .destructive) {
                    showSignOutConfirm = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have \(offlineSync.pendingCount) change(s) waiting to sync. Sync now or sign out anyway?")
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.logout() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
