import SwiftData
import SwiftUI

@main
struct StormCRMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer: ModelContainer
    @StateObject private var appEnvironment: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            container = try OfflineStore.makeContainer()
        } catch {
            fatalError("Failed to create offline ModelContainer: \(error)")
        }
        modelContainer = container
        _appEnvironment = StateObject(wrappedValue: AppEnvironment(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.auth)
                .environmentObject(appEnvironment.branding)
                .environmentObject(appEnvironment.offlineSync)
                .environmentObject(appEnvironment.priceBookPins)
                .environmentObject(appEnvironment.appearance)
                .modelContainer(modelContainer)
                .tint(StormTheme.coral)
                .onOpenURL { url in
                    appEnvironment.handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        appEnvironment.offlineSync.handleAppBackgrounded(apiClient: appEnvironment.apiClient)
                    case .active:
                        appEnvironment.offlineSync.handleAppForegrounded()
                        appEnvironment.offlineSync.flushOutbox()
                    default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var appearanceSettings: AppearanceSettings

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                        .task {
                            try? await auth.ensureUserLoaded()
                            env.bootstrapAfterLogin()
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
        .preferredColorScheme(appearanceSettings.appearance.preferredColorScheme)
    }
}
