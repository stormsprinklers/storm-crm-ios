import SwiftUI

@main
struct StormCRMApp: App {
    @StateObject private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.auth)
                .environmentObject(appEnvironment.branding)
                .tint(StormTheme.coral)
                .onOpenURL { url in
                    appEnvironment.handleDeepLink(url)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                        .task {
                            await env.branding.load(api: env.apiClient)
                            await env.voice.prepare()
                        }
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut, value: auth.isAuthenticated)

            if auth.isAuthenticated {
                VoiceCallBar(voice: env.voice)
                    .padding(.top, 4)
            }
        }
        .background(StormTheme.page.ignoresSafeArea())
    }
}
