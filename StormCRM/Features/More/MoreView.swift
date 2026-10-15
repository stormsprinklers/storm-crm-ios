import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var branding: CompanyBranding
    @EnvironmentObject private var offlineSync: OfflineSyncManager
    @EnvironmentObject private var appearanceSettings: AppearanceSettings

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
                        NavigationLink {
                            CompanySwitcherView()
                        } label: {
                            LabeledContent("Company", value: branding.companyName)
                        }
                    }
                }

                Section {
                    Picker(selection: $appearanceSettings.appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Appearance", systemImage: "moon.circle")
                    }
                } footer: {
                    Text("Choose System to match your iPhone Light/Dark setting. Light or Dark locks the app to that look.")
                }

                Section("Tools") {
                    NavigationLink { NotificationSettingsView() } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    NavigationLink { VoiceErrorsView(voice: env.voice) } label: { VoiceErrorsLabel(voice: env.voice) }
                    NavigationLink {
                        CRMFieldToolView(tool: .vehicles)
                    } label: {
                        Label("Vehicles", systemImage: "truck.box")
                    }

                    NavigationLink {
                        HolidayQuotesView()
                    } label: {
                        Label("Holiday Lighting", systemImage: "lightbulb.2")
                    }

                    NavigationLink {
                        CRMFieldToolView(tool: .priceBook)
                    } label: {
                        Label("Price Book", systemImage: "book.closed")
                    }

                    NavigationLink {
                        VoiceStatusView()
                    } label: {
                        Label("Phone connection", systemImage: "phone.connection")
                    }

                    NavigationLink {
                        StormAiChatView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(branding.aiName, systemImage: "sparkles")
                            Text("Chat, part photos, live voice & video")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

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

                if branding.termsOfServiceURL != nil || branding.privacyPolicyURL != nil {
                    Section("Legal") {
                        if let url = branding.termsOfServiceURL {
                            Link(destination: url) {
                                Label("Terms of Service", systemImage: "doc.text")
                            }
                        }
                        if let url = branding.privacyPolicyURL {
                            Link(destination: url) {
                                Label("Privacy Policy", systemImage: "hand.raised")
                            }
                        }
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

private struct VoiceErrorsView: View {
    @ObservedObject var voice: VoiceManager
    var body: some View {
        List {
            if voice.reportedErrors.isEmpty { Text("No sustained errors.").foregroundStyle(.secondary) }
            ForEach(voice.reportedErrors) { error in
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.message)
                    Text(error.occurredAt.formatted()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Errors").onAppear { voice.markErrorsRead() }
        .toolbar { Button("Clear") { voice.clearReportedErrors() } }
    }
}

private struct VoiceErrorsLabel: View {
    @ObservedObject var voice: VoiceManager
    var body: some View {
        HStack {
            Label("Errors", systemImage: "exclamationmark.bubble")
            Spacer()
            if voice.unreadErrorCount > 0 { Text("\(voice.unreadErrorCount)").font(.caption.bold()).padding(6).background(Color.orange.opacity(0.15)).clipShape(Capsule()) }
        }
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var push = PushNotificationManager.shared
    @State private var busy = false
    var body: some View {
        List {
            Section {
                LabeledContent("iPhone permission", value: push.permissionStatus)
                LabeledContent("Registration", value: push.registrationStatus)
                if let configured = push.serverConfigured {
                    LabeledContent("Server", value: configured ? "Configured" : "Apple push setup required")
                }
                Button("Enable / retry registration") {
                    Task {
                        busy = true
                        await push.requestAuthorizationIfNeeded()
                        await push.syncToken(api: env.apiClient)
                        await push.checkServer(api: env.apiClient)
                        busy = false
                    }
                }.disabled(busy)
                Button("Open iPhone notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Send test notification") {
                    Task { busy = true; await push.sendTest(api: env.apiClient); busy = false }
                }.disabled(busy || push.serverConfigured == false)
            } header: { Text("Push notifications") } footer: {
                Text("Allow alerts, sounds and badges to receive new messages while Radar is closed or your iPhone is locked.")
            }
            if let message = push.lastError { Section("Status") { Text(message).foregroundStyle(.secondary) } }
            if let message = push.testResult { Section { Text(message) } }
        }
        .navigationTitle("Notifications")
        .task {
            await push.requestAuthorizationIfNeeded()
            await push.syncToken(api: env.apiClient)
            await push.checkServer(api: env.apiClient)
        }
    }
}
