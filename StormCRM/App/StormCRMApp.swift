import SwiftUI

@main
struct StormCRMApp: App {
    @StateObject private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appEnvironment)
                .onOpenURL { url in
                    appEnvironment.handleDeepLink(url)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        Group {
            if env.auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: env.auth.isAuthenticated)
    }
}
