import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm = LoginViewModel()
    @State private var goToSignup = false
    // Drives the logo spin. It's a loading indicator: spins only while the login call is
    // in-flight and settles upright when the call finishes or fails (mirrors Android).
    @State private var spinning = false
    @State private var showPassword = false
    @FocusState private var focused: Bool

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
        // A "Done" key above the keyboard — the login screen doesn't scroll, so interactive
        // swipe-to-dismiss had nothing to grab; this always lets the user drop the keyboard.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
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
                .rotationEffect(.degrees(spinning ? 360 : 0))
                // Continuous spin while loading; a gentle ease-out settle when it stops.
                .animation(spinning
                           ? .linear(duration: 1).repeatForever(autoreverses: false)
                           : .easeOut(duration: 0.25),
                           value: spinning)
                .onChange(of: vm.isLoading) { _, loading in spinning = loading }
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

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    VStack(spacing: 0) {
                        TextField("Email", text: $vm.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .frame(maxWidth: .infinity, alignment: .leading)   // tap anywhere in the row focuses
                            .padding(Theme.Spacing.m)
                        Divider()
                        HStack(spacing: Theme.Spacing.s) {
                            Group {
                                if showPassword {
                                    TextField("Password", text: $vm.password)
                                } else {
                                    SecureField("Password", text: $vm.password)
                                }
                            }
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .frame(maxWidth: .infinity, alignment: .leading)   // tap anywhere in the row focuses
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            .sensoryFeedback(.selection, trigger: showPassword)
                        }
                        .padding(Theme.Spacing.m)
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))

                    if let emailError = vm.emailError {
                        Text(emailError)
                            .foregroundStyle(.red) // field-level feedback (email)
                            .font(.caption)
                    }
                    if let passwordError = vm.passwordError {
                        Text(passwordError)
                            .foregroundStyle(.red) // field-level feedback (password)
                            .font(.caption)
                    }
                }

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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: Theme.CornerRadius.button))
                .tint(Theme.brandTeal)
                // Enabled even when fields are empty so tapping surfaces the
                // "Email is required" / "Password is required" messages (mirrors Android).
                .disabled(vm.isLoading)
            }
        }
        // Native haptics: error buzz when a login attempt fails / validation trips.
        .sensoryFeedback(.error, trigger: vm.errorMessage)
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
