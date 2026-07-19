import SwiftUI

/// Modal approval flow: amount, signature pad, and Terms of Service acknowledgment.
struct EstimateApprovalSheet: View {
    @EnvironmentObject private var branding: CompanyBranding
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let estimateTotal: Double
    @Binding var isSaving: Bool
    /// Called with PNG bytes when the user confirms approval. Return true to dismiss.
    var onApprove: (Data) async -> Bool

    @State private var hasSignatureInk = false
    @State private var localError: String?
    @StateObject private var signatureController = EstimateSignatureController()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Approve Estimate: \(estimateTotal.formatted(.currency(code: "USD")))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(StormTheme.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Customer signature")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                EstimateSignaturePad(hasInk: $hasSignatureInk, controller: signatureController)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(StormTheme.ice, lineWidth: 1)
                    )

                HStack {
                    Button("Clear") {
                        signatureController.clear()
                        hasSignatureInk = false
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(!hasSignatureInk || isSaving)

                    Spacer(minLength: 0)
                }

                if let localError {
                    Text(localError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                termsFooter

                Spacer(minLength: 0)

                Button {
                    Task { await approve() }
                } label: {
                    Label(
                        isSaving ? "Approving…" : "Approve",
                        systemImage: "checkmark.seal.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StormPrimaryButtonStyle())
                .disabled(isSaving || !hasSignatureInk)
            }
            .padding()
            .background(StormTheme.page.ignoresSafeArea())
            .navigationTitle("Approve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private var termsFooter: some View {
        Group {
            if let url = branding.termsOfServiceURL {
                (
                    Text("All services are subject to our ")
                        .foregroundStyle(.secondary)
                    + Text("Terms of Service")
                        .foregroundStyle(StormTheme.sky)
                        .underline()
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { openURL(url) }
                .accessibilityAddTraits(.isLink)
            } else {
                (
                    Text("All services are subject to our ")
                        .foregroundStyle(.secondary)
                    + Text("Terms of Service")
                        .foregroundStyle(.secondary)
                        .underline()
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Terms of Service (not configured yet)")
                .accessibilityHint("Company terms of service link is not set up yet")
            }
        }
    }

    private func approve() async {
        guard let png = signatureController.pngData() else {
            localError = "Customer signature is required"
            return
        }
        localError = nil
        let succeeded = await onApprove(png)
        if succeeded {
            signatureController.clear()
            hasSignatureInk = false
            dismiss()
        }
    }
}
