import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment

    private var showReporting: Bool {
        env.auth.user.map { UserRoles.canViewReporting($0.role) } ?? false
    }

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

            if showReporting {
                ReportingHubView()
                    .tabItem { Label("Reports", systemImage: "chart.bar") }
                    .tag(MainTab.reporting)
            }

            InboxHubView()
                .tabItem { Label("Inbox", systemImage: "message") }
                .tag(MainTab.inbox)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(MainTab.more)
        }
        .sheet(item: $env.paymentReturn) { payment in
            PaymentReturnSheet(payment: payment)
        }
    }
}
