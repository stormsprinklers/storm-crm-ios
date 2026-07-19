import SwiftUI

/// Modal approval flow: amount, signature pad, and Terms of Service acknowledgment.
struct EstimateApprovalSheet: View {
    @EnvironmentObject private var branding: CompanyBranding
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let estimateTotal: Double
    let canApprove: Bool
    @Binding var isSaving: Bool
    /// Called with PNG bytes when the user confirms approval. Return `nil` on success, or an error message.
    var onApprove: (Data) async -> String?

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

                if !canApprove {
                    Text("Add at least one line item before approving.")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

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
                        localError = nil
                    }
                    .buttonStyle(StormSecondaryButtonStyle())
                    .disabled(!hasSignatureInk || isSaving)

                    Spacer(minLength: 0)
                }

                if let localError {
                    Text(localError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                termsFooter

                Spacer(minLength: 0)

                Button {
                    Task { await approve() }
                } label: {
                    Label(
                        isSaving ? "Approving…" : "Approve with signature",
                        systemImage: "checkmark.seal.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StormPrimaryButtonStyle())
                .disabled(isSaving || !hasSignatureInk || !canApprove)
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
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var termsFooter: some View {
        Group {
            if branding.termsOfServiceURL != nil || branding.privacyPolicyURL != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let url = branding.termsOfServiceURL {
                        legalLinkRow(prefix: "All services are subject to our ", label: "Terms of Service", url: url)
                    } else {
                        inactiveTermsRow
                    }
                    if let url = branding.privacyPolicyURL {
                        legalLinkRow(prefix: "See also our ", label: "Privacy Policy", url: url)
                    }
                }
            } else {
                inactiveTermsRow
            }
        }
    }

    private var inactiveTermsRow: some View {
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

    private func legalLinkRow(prefix: String, label: String, url: URL) -> some View {
        (
            Text(prefix)
                .foregroundStyle(.secondary)
            + Text(label)
                .foregroundStyle(StormTheme.sky)
                .underline()
        )
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture { openURL(url) }
        .accessibilityAddTraits(.isLink)
    }

    private func approve() async {
        guard canApprove else {
            localError = "Add at least one line item before approving."
            return
        }
        guard let png = signatureController.pngData() else {
            localError = "Customer signature is required"
            return
        }
        localError = nil
        if let message = await onApprove(png) {
            localError = message
            return
        }
        signatureController.clear()
        hasSignatureInk = false
        dismiss()
    }
}
