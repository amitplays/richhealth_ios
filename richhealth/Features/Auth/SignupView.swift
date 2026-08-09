import SwiftUI

/// Multi-step signup: Account → Personal → Physical → Goals → Lifestyle & Health → OTP.
/// Card-based layout matches Android OnboardingActivity (MaterialCardView + styled inputs).
/// 5-step form collects all key onboarding data; OTP step uses Form.
struct SignupView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm = SignupViewModel()

    var body: some View {
        Group {
            if vm.isAccountCreated {
                otpStepView
            } else {
                formStepsView
            }
        }
        .navigationTitle(vm.isAccountCreated ? "Verify email" : stepTitle)
        .navigationBarBackButtonHidden(vm.isAccountCreated)
    }

    private var stepTitle: String {
        ["Your account", "Personal info", "Your body", "Goals & diet", "Lifestyle"][safe: vm.step] ?? "Create account"
    }

    // ─── OTP Step ─────────────────────────────────────────────────────────────

    private var otpStepView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label("Check your inbox", systemImage: "envelope.circle.fill")
                        .font(.headline)
                    Text("We sent a 6-digit code to **\(vm.email)**. Enter it below to verify your email.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section {
                TextField("6-digit code", text: $vm.otpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title3.monospacedDigit())
                    .onChange(of: vm.otpCode) { _, new in
                        if new.count > 6 { vm.otpCode = String(new.prefix(6)) }
                    }
            }

            if let msg = vm.otpMessage {
                Section {
                    if msg.hasPrefix("Code sent") {
                        Text(msg).foregroundStyle(.secondary).font(.footnote)
                    } else {
                        Text(msg).foregroundStyle(Color.red).font(.footnote) // error feedback
                    }
                }
            }

            Section {
                Button {
                    Task { await vm.verifyOTP(auth: appEnv.auth) }
                } label: {
                    if vm.isOTPLoading {
                        HStack { ProgressView().padding(.trailing, Theme.Spacing.xs); Text("Verifying…") }
                    } else {
                        Text("Verify email")
                    }
                }
                .disabled(vm.isOTPLoading || vm.otpCode.count != 6)

                Button("Resend code") {
                    Task { await vm.sendOTP(auth: appEnv.auth) }
                }
                .disabled(vm.isOTPLoading)
                .foregroundStyle(Theme.brandTeal)
            }

            Section {
                Button("Skip for now") {
                    Task { await vm.skipOTP(auth: appEnv.auth) }
                }
                .foregroundStyle(.secondary)
            } footer: {
                Text("You can verify your email later from your profile.")
            }
        }
    }

    // ─── Multi-step card form ─────────────────────────────────────────────────
    // Mirrors Android layout: step bars + circle icon header + GlassCard with styled fields.

    private var formStepsView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                stepBars
                stepHeaderIcon

                GlassCard {
                    VStack(spacing: Theme.Spacing.m) {
                        switch vm.step {
                        case 0: stepAccountContent
                        case 1: stepPersonalContent
                        case 2: stepPhysicalContent
                        case 3: stepGoalsContent
                        default: stepLifestyleContent
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)

                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red) // error feedback
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.m)
                }

                VStack(spacing: Theme.Spacing.s) {
                    if vm.step == SignupViewModel.totalSteps - 1 {
                        Button {
                            Task { await vm.submit(auth: appEnv.auth) }
                        } label: {
                            Group {
                                if vm.isLoading {
                                    HStack(spacing: Theme.Spacing.s) {
                                        ProgressView().tint(.white) // contrast on teal button
                                        Text("Creating account…")
                                    }
                                } else {
                                    Text("Create account")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                        .disabled(vm.isLoading)
                    } else {
                        Button {
                            vm.next()
                        } label: {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandTeal)
                    }

                    if vm.step > 0 {
                        Button("Back") { vm.back() }
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ─── Step 0: Account ─────────────────────────────────────────────────────

    @ViewBuilder private var stepAccountContent: some View {
        brandedField("Full name") {
            TextField("Full name", text: $vm.name)
                .textContentType(.name)
                .autocorrectionDisabled()
        }
        brandedField("Email") {
            TextField("Email address", text: $vm.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        brandedField("Phone (optional)") {
            TextField("Phone number", text: $vm.phoneNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
        }
        brandedField("Password") {
            SecureField("Min. 6 characters", text: $vm.password)
                .textContentType(.newPassword)
        }
        brandedField("Confirm password") {
            SecureField("Re-enter password", text: $vm.confirmPassword)
                .textContentType(.newPassword)
        }
    }

    // ─── Step 1: Personal ────────────────────────────────────────────────────

    @ViewBuilder private var stepPersonalContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Gender")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Gender", selection: $vm.gender) {
                Text("Select").tag("")
                ForEach(vm.genderOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Date of birth")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                DatePicker(
                    "",
                    selection: $vm.dateOfBirth,
                    in: ...Calendar.current.date(byAdding: .year, value: -10, to: .now)!,
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(Theme.brandTeal)
                Spacer()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }

        brandedField("Location (optional)") {
            TextField("City, Country", text: $vm.location)
                .textContentType(.addressCityAndState)
                .autocorrectionDisabled()
        }
    }

    // ─── Step 2: Physical ────────────────────────────────────────────────────

    @ViewBuilder private var stepPhysicalContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Height")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(Int(vm.heightCm)) cm")
                    .font(.subheadline)
                Spacer()
                Stepper("", value: $vm.heightCm, in: 100...250, step: 1)
                    .labelsHidden()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Weight")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: "%.1f kg", vm.weightKg))
                    .font(.subheadline)
                Spacer()
                Stepper("", value: $vm.weightKg, in: 30...250, step: 0.5)
                    .labelsHidden()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }

        pickerField("Blood type (optional)") {
            Picker("Blood type", selection: $vm.bloodType) {
                Text("Don't know / skip").tag("")
                ForEach(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"], id: \.self) {
                    Text($0).tag($0)
                }
            }
        }
    }

    // ─── Step 3: Goals & Diet ────────────────────────────────────────────────

    @ViewBuilder private var stepGoalsContent: some View {
        pickerField("Primary health goal") {
            Picker("Goal", selection: $vm.primaryGoal) {
                ForEach(vm.goalOptions, id: \.self) { Text($0).tag($0) }
            }
        }
        pickerField("Activity level") {
            Picker("Activity level", selection: $vm.activityLevel) {
                ForEach(1...5, id: \.self) { level in
                    Text(vm.activityOptions[level - 1]).tag(level)
                }
            }
        }
        pickerField("Diet type") {
            Picker("Diet", selection: $vm.dietType) {
                ForEach(vm.dietOptions, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    // ─── Step 4: Lifestyle & Health ──────────────────────────────────────────
    // Mirrors Android OnboardingActivity steps 7-15: sleep, smoking, alcohol, caffeine,
    // medical conditions, allergies.

    @ViewBuilder private var stepLifestyleContent: some View {
        Text("These are all optional — skip any you prefer not to share.")
            .font(.caption)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Average sleep hours")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: "%.1f hrs", vm.sleepHours))
                    .font(.subheadline)
                Spacer()
                Stepper("", value: $vm.sleepHours, in: 3...12, step: 0.5)
                    .labelsHidden()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }

        pickerField("Smoking") {
            Picker("Smoking", selection: $vm.smokingStatus) {
                Text("Never").tag("never")
                Text("I quit").tag("ex")
                Text("Only socially").tag("social")
                Text("Sometimes").tag("occasional")
                Text("Daily habit").tag("regular")
            }
        }

        pickerField("Alcohol") {
            Picker("Alcohol", selection: $vm.alcoholConsumption) {
                Text("None").tag("None")
                Text("Rarely").tag("Rarely")
                Text("Special occasions").tag("Special Occasions")
                Text("Socially").tag("Socially")
                Text("Regularly").tag("Regularly")
                Text("Frequently").tag("Frequently")
            }
        }

        pickerField("Caffeine") {
            Picker("Caffeine", selection: $vm.caffeineHabit) {
                Text("No caffeine").tag("none")
                Text("Tea").tag("tea")
                Text("Coffee").tag("coffee")
                Text("Energy drinks").tag("energy_drinks")
            }
        }

        brandedField("Medical conditions (optional)") {
            TextField("E.g. Diabetes, Hypertension", text: $vm.medicalConditions, axis: .vertical)
                .lineLimit(1...3)
        }

        brandedField("Allergies (optional)") {
            TextField("E.g. Peanuts, Dairy, Gluten", text: $vm.allergies, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // ── Step progress bars ────────────────────────────────────────────────────

    private var stepBars: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<SignupViewModel.totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= vm.step ? Theme.brandTeal : Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: vm.step)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.m)
    }

    // ── Step icon header ──────────────────────────────────────────────────────
    // Circular step icon + caption — mirrors Android's 80dp circular MaterialCardView icons.

    private var stepHeaderIcon: some View {
        let icons    = ["person.badge.key.fill", "person.fill", "figure.stand",
                        "target", "heart.text.clipboard"]
        let captions = ["Secure your account", "Tell us about yourself",
                        "Your body metrics", "Goals & diet", "Lifestyle & health"]
        return VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle()
                    .fill(Theme.brandTeal.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: icons[safe: vm.step] ?? "person.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.brandTeal)
            }
            Text(captions[safe: vm.step] ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
    }

    // ── Branded field helpers ─────────────────────────────────────────────────

    // Plain label + filled background, no material/blur — fast native iOS field appearance.
    @ViewBuilder private func brandedField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .padding(Theme.Spacing.m)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }
    }

    // Consistent with brandedField: label above, same rounded glass background.
    @ViewBuilder private func pickerField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                content()
                    .tint(Theme.brandTeal)
                    .pickerStyle(.menu)
                Spacer()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    NavigationStack { SignupView() }
        .environment(AppEnvironment())
}
