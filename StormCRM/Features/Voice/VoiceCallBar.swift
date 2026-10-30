import SwiftUI
import AVFoundation

struct VoiceCallBar: View {
    @ObservedObject var voice: VoiceManager
    var openCall: () -> Void = {}

    var body: some View {
        if voice.isInCall || voice.status.contains("Connecting") || voice.status.contains("Calling") {
            HStack(spacing: 12) {
                Button(action: openCall) {
                HStack {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.activePhone ?? "Active call")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(voice.status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open active call")
                Spacer()
                Button { voice.toggleSpeaker() } label: {
                    Image(systemName: voice.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.2")
                }
                .foregroundStyle(voice.isSpeakerOn ? .yellow : .white)
                .accessibilityLabel(voice.isSpeakerOn ? "Turn speaker off" : "Turn speaker on")
                Button(voice.isMuted ? "Unmute" : "Mute") {
                    voice.toggleMute()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                Button("End") {
                    voice.hangUp()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.85))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(StormTheme.brandNavy)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in voice.refreshAudioRoute() }
            .onAppear { voice.refreshAudioRoute() }
            .shadow(radius: 4)
            .transition(.move(edge: .top))
        }
    }
}

struct ActiveVoiceCallView: View {
    @ObservedObject var voice: VoiceManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "phone.fill").font(.system(size: 52))
                Text(voice.activePhone ?? "Active call").font(.title2).multilineTextAlignment(.center)
                Text(voice.status).foregroundStyle(.secondary)
                Button(voice.isMuted ? "Unmute" : "Mute", systemImage: voice.isMuted ? "mic.slash.fill" : "mic.fill") { voice.toggleMute() }
                    .buttonStyle(.bordered)
                Button(voice.isSpeakerOn ? "Speaker on" : "Speaker off", systemImage: voice.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.2") { voice.toggleSpeaker() }
                    .buttonStyle(.bordered)
                Button("End call", systemImage: "phone.down.fill") { voice.hangUp(); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.red)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Call")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
        }
        .onChange(of: voice.isInCall) { _, active in if !active { dismiss() } }
    }
}
