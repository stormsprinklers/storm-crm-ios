import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment

    private var showReporting: Bool {
        env.auth.user.map { UserRoles.canViewReporting($0.role) } ?? false
    }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house") }

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            VisitsListView()
                .tabItem { Label("Visits", systemImage: "wrench.and.screwdriver") }

            CustomersListView()
                .tabItem { Label("Customers", systemImage: "person.2") }

            if showReporting {
                ReportingHubView()
                    .tabItem { Label("Reports", systemImage: "chart.bar") }
            }

            InboxHubView()
                .tabItem { Label("Inbox", systemImage: "message") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .sheet(item: $env.paymentReturn) { payment in
            PaymentReturnSheet(payment: payment)
        }
    }
}
