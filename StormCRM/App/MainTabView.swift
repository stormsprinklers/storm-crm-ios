import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            MainBottomTabBar(selection: $env.selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $env.paymentReturn) { payment in
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

    @ViewBuilder
    private var tabContent: some View {
        switch env.selectedTab {
        case .dashboard:
            DashboardView()
        case .schedule:
            ScheduleView()
        case .customers:
            CustomersListView()
        case .messages:
            MessagesHubView()
        case .more:
            MoreView()
        }
    }
}

private struct MainBottomTabBar: View {
    @Binding var selection: MainTab

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
