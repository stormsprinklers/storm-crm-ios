import SwiftUI

struct EstimateSendComposer: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let estimateId: String
    var scheduled = false
    var onSent: () async -> Void
    @State private var preview: Preview?
    @State private var channel = "sms"
    @State private var subject = ""
    @State private var message = ""
    @State private var sendAt = Date().addingTimeInterval(3600)
    @State private var sending = false
    @State private var error: String?
    struct Preview: Decodable { let link: String; let email: String?; let phone: String?; let subject: String; let message: String }
    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Picker("Send by", selection: $channel) {
                        if preview.phone?.isEmpty == false { Text("Text").tag("sms") }
                        if preview.email?.isEmpty == false { Text("Email").tag("email") }
                    }.pickerStyle(.segmented)
                    LabeledContent("To", value: (channel == "sms" ? preview.phone : preview.email) ?? "")
                    if channel == "email" { TextField("Subject", text: $subject) }
                    TextField("Message", text: $message, axis: .vertical).lineLimit(5...12)
                    if scheduled { DatePicker("Send at", selection: $sendAt, in: Date()...) }
                    Text(preview.link).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                } else if error == nil { ProgressView("Loading message…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(scheduled ? "Schedule send" : "Send estimate").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await send() } } label: { if sending { ProgressView() } else { Image(systemName: "paperplane.fill") } }
                        .accessibilityLabel("Send estimate")
                        .disabled(sending || preview == nil || (preview?.phone?.isEmpty != false && preview?.email?.isEmpty != false) || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                do {
                    let value: Preview = try await env.apiClient.get(path: APIPath.estimateSend(estimateId))
                    if value.phone?.isEmpty != false && value.email?.isEmpty != false { error = "Add a customer phone number or email address before sending." }
                    preview = value; subject = value.subject; message = value.message
                    channel = value.phone?.isEmpty == false ? "sms" : "email"
                } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
            }
        }
    }
    private func send() async {
        sending = true; error = nil; defer { sending = false }
        do {
            struct Body: Encodable { let channel: String; let subject: String; let message: String; let runAt: String? }
            let _: EmptyResponse = try await env.apiClient.post(path: APIPath.estimateSend(estimateId), body: Body(channel: channel, subject: subject, message: message, runAt: scheduled ? ISO8601DateFormatter().string(from: sendAt) : nil))
            await onSent(); dismiss()
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }
}
