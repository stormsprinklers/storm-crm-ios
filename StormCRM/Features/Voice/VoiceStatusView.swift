import SwiftUI
import UIKit

struct VoiceStatusView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        VoiceConnectionDetails(voice: env.voice, companyName: env.branding.companyName)
    }
}

private struct VoiceConnectionDetails: View {
    @ObservedObject var voice: VoiceManager
    let companyName: String
    @State private var refreshing = false

    var body: some View {
        List {
            Section("Phone connection") {
                LabeledContent("Company", value: companyName)
                LabeledContent("Status", value: voice.status)
                LabeledContent("Incoming calls", value: voice.isListeningForCalls ? "Registered" : "Not registered")
                if let error = voice.lastError { Text(error).foregroundStyle(.red) }
                Button {
                    Task {
                        refreshing = true
                        await voice.prepare()
                        refreshing = false
                    }
                } label: {
                    if refreshing { ProgressView("Connecting…") } else { Text("Refresh connection") }
                }
                .disabled(refreshing || voice.isInCall)
            }
            Section {
                Button("Open microphone settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } footer: {
                Text("Calls require internet access and microphone permission. Incoming calls also require your company's phone routing to ring your app.")
            }
        }
        .navigationTitle("Phone connection")
    }
}
