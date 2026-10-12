import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            MainBottomTabBar(selection: $env.selectedTab, voice: env.voice)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: Binding(
            get: {
                guard let payment = env.paymentReturn else { return nil }
                if env.collectingPaymentVisitId == payment.visitId { return nil }
                return payment
            },
            set: { env.paymentReturn = $0 }
        )) { payment in
            PaymentReturnSheet(payment: payment)
        }
        .onChange(of: push.pendingConversationId) { _, _ in
            env.applyPushNavigation(from: push)
        }
        .onChange(of: push.pendingVisitId) { _, _ in
            env.applyPushNavigation(from: push)
        }
        .onChange(of: push.pendingCustomerId) { _, _ in
            env.applyPushNavigation(from: push)
        }
        .onChange(of: push.pendingEstimateId) { _, _ in
            env.applyPushNavigation(from: push)
        }
        .onChange(of: push.pendingDeepLink) { _, _ in
            env.applyPushNavigation(from: push)
        }
    }

    /// Keep every tab root mounted so NavigationStacks (e.g. an open visit on Schedule)
    /// survive switching away and back. A `switch` would recreate the tab and pop to root.
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            tabPane(.dashboard) { DashboardView() }
            tabPane(.schedule) { ScheduleView() }
            tabPane(.customers) { CustomersListView() }
            tabPane(.messages) { MessagesHubView() }
            tabPane(.more) { MoreView() }
        }
    }

    @ViewBuilder
    private func tabPane<Content: View>(
        _ tab: MainTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = env.selectedTab == tab
        content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .zIndex(selected ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MainBottomTabBar: View {
    @Binding var selection: MainTab
    @ObservedObject var voice: VoiceManager

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            if tab == .more && voice.unreadErrorCount > 0 { Text("\(voice.unreadErrorCount)").font(.caption2.bold()).foregroundStyle(.orange) }
                            Text(tab.title)
                                .font(.caption2.weight(selection == tab ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selection == tab ? StormTheme.coral : StormTheme.navy.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .background(Color(.systemBackground))
        }
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
