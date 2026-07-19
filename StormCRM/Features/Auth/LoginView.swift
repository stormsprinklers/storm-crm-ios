import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var isLoading = false
    @State private var isPasswordVisible = false

    private var forgotPasswordURL: URL? {
        URL(string: "\(AppConfig.apiBaseURL)/forgot-password")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        StormLogoMark()
                        Text("Radar")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(StormTheme.navy)
                        Text("Field technician app")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    if let pending = auth.pendingMfa {
                        mfaCard(pending)
                    } else {
                        passwordCard
                    }
                }
                .padding()
            }
            .background(StormTheme.page.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var passwordCard: some View {
        VStack(spacing: 14) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StormTheme.ice, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(StormTheme.navy.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(StormTheme.ice, lineWidth: 1)
            )

            if let error = auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    isLoading = true
                    await auth.login(email: email, password: password)
                    isLoading = false
                }
            } label: {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                    }
                    Spacer()
                }
            }
            .buttonStyle(StormPrimaryButtonStyle())
            .disabled(email.isEmpty || password.isEmpty || isLoading)

            if let forgotPasswordURL {
                Link("Forgot Password?", destination: forgotPasswordURL)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(StormTheme.sky)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: StormTheme.navy.opacity(0.08), radius: 12, y: 4)
    }

    private func mfaCard(_ pending: PendingMfaChallenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verify it's you")
                .font(.headline)
            Text("Enter the code we texted to \(pending.phoneMasked).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            #if DEBUG
            if let debug = pending.debugCode {
                Text("Debug code: \(debug)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }
            #endif

            TextField("6-digit code", text: $mfaCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StormTheme.ice, lineWidth: 1)
                )

            if let error = auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    isLoading = true
                    await auth.verifyMfa(code: mfaCode)
                    isLoading = false
                }
            } label: {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify")
                    }
                    Spacer()
                }
            }
            .buttonStyle(StormPrimaryButtonStyle())
            .disabled(mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 || isLoading)

            HStack {
                Button("Resend code") {
                    Task { await auth.resendMfa() }
                }
                .font(.subheadline)
                Spacer()
                Button("Back") {
                    mfaCode = ""
                    auth.cancelMfa()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: StormTheme.navy.opacity(0.08), radius: 12, y: 4)
    }
}
