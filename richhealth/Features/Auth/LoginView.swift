import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm = LoginViewModel()
    @State private var goToSignup = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                logoSection
                    .padding(.top, Theme.Spacing.xl)
                formCard
                signupCTA
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goToSignup) {
            SignupView()
        }
    }

    // ── Logo section ──────────────────────────────────────────────────────────
    // Mirrors Android splash/login: centered logo, teal app name, gray tagline.

    private var logoSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
            Text("RichHealth")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.brandTeal)
            Text("Your health, intelligently rich")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // ── Form card ─────────────────────────────────────────────────────────────

    private var formCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Welcome Back")
                    .font(.title2.bold())

                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red) // error feedback
                        .font(.footnote)
                }

                VStack(spacing: 0) {
                    TextField("Email", text: $vm.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(Theme.Spacing.m)
                    Divider()
                    SecureField("Password", text: $vm.password)
                        .textContentType(.password)
                        .padding(Theme.Spacing.m)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))

                HStack {
                    Spacer()
                    Button("Forgot password?") { /* TODO: password reset flow */ }
                        .font(.subheadline)
                        .foregroundStyle(Theme.brandTeal)
                }

                Button {
                    Task { await vm.login(auth: appEnv.auth) }
                } label: {
                    Group {
                        if vm.isLoading {
                            HStack(spacing: Theme.Spacing.s) {
                                ProgressView().tint(.white) // contrast on teal button
                                Text("Signing in…")
                            }
                        } else {
                            Text("Log in")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandTeal)
                .disabled(vm.isLoading || vm.email.isEmpty || vm.password.isEmpty)
            }
        }
    }

    // ── Sign up CTA ───────────────────────────────────────────────────────────

    private var signupCTA: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .foregroundStyle(.secondary)
            Button("Sign Up") { goToSignup = true }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.brandTeal)
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack { LoginView() }
        .environment(AppEnvironment())
}
