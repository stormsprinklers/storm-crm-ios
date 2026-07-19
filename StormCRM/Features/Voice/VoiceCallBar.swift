import SwiftUI

struct VoiceCallBar: View {
    @ObservedObject var voice: VoiceManager

    var body: some View {
        if voice.isInCall || voice.status.contains("Connecting") || voice.status.contains("Calling") {
            HStack(spacing: 12) {
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
                Spacer()
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
            .shadow(radius: 4)
            .transition(.move(edge: .top))
        } else if let error = voice.lastError, !error.isEmpty {
            voiceBanner(error, isError: true)
        } else if shouldShowVoiceStatus {
            voiceBanner(voice.status, isError: false)
        }
    }

    private var shouldShowVoiceStatus: Bool {
        let status = voice.status.lowercased()
        return status.contains("unavailable")
            || status.contains("simulator")
            || status.contains("failed")
    }

    @ViewBuilder
    private func voiceBanner(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if isError {
                Button {
                    voice.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background((isError ? Color.red : Color.orange).opacity(0.9))
        .task(id: message) {
            guard isError else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            voice.clearError()
        }
    }
}
