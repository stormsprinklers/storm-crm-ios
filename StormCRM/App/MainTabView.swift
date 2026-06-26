import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            VisitsListView()
                .tabItem { Label("Visits", systemImage: "wrench.and.screwdriver") }

            TeamInboxView()
                .tabItem { Label("Inbox", systemImage: "message") }

            MeView()
                .tabItem { Label("Me", systemImage: "person.circle") }
        }
        .sheet(item: $env.paymentReturn) { payment in
            PaymentReturnSheet(payment: payment)
        }
    }
}
