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
        }
    }
}
