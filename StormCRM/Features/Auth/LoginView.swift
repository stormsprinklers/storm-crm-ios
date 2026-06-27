import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var branding: CompanyBranding
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        AsyncLogoImage(urlString: branding.logoUrl, height: 56)
                        Text(branding.companyName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(StormTheme.navy)
                        Text("Field technician app")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

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

                        SecureField("Password", text: $password)
                            .textContentType(.password)
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
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: StormTheme.navy.opacity(0.08), radius: 12, y: 4)
                }
                .padding()
            }
            .background(StormTheme.page.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}
