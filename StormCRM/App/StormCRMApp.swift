import SwiftUI

@main
struct StormCRMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                            env.priceBookPins.setUserId(auth.user?.id)
                            await env.branding.load(api: env.apiClient)
                            await env.voice.prepare()
                            await PushNotificationManager.shared.requestAuthorizationIfNeeded()
                            await PushNotificationManager.shared.syncToken(api: env.apiClient)
                        }
                        .onChange(of: auth.user?.id) { _, userId in
                            env.priceBookPins.setUserId(userId)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .pushDeviceTokenUpdated)) { _ in
                            Task { await PushNotificationManager.shared.syncToken(api: env.apiClient) }
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
