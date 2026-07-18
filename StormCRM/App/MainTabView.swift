import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var push = PushNotificationManager.shared

    var body: some View {
        TabView(selection: $env.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house") }
                .tag(MainTab.dashboard)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(MainTab.schedule)

            CustomersListView()
                .tabItem { Label("Customers", systemImage: "person.2") }
                .tag(MainTab.customers)

            MessagesHubView()
                .tabItem { Label("Messages", systemImage: "message") }
                .tag(MainTab.messages)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(MainTab.more)
        }
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
}
