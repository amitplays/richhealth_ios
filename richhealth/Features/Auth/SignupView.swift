import SwiftUI

/// Multi-step signup mirroring Android's OnboardingActivity (up to 21 conditional steps).
/// Card-based layout: step bars + circular icon header + GlassCard with styled fields.
/// The active step list is dynamic (see SignupViewModel.activeSteps); the final step
/// submits the account, then an OTP step verifies the email.
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
        .navigationTitle(vm.isAccountCreated ? "Verify email" : vm.currentStep.title)
        .navigationBarBackButtonHidden(vm.isAccountCreated)
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

    private var formStepsView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                stepBars
                stepHeaderIcon

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        stepContent
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

                navigationButtons
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .id(vm.stepIndex) // reset scroll position between steps
    }

    private var navigationButtons: some View {
        VStack(spacing: Theme.Spacing.s) {
            if vm.isLastStep {
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

            if vm.stepIndex > 0 {
                Button("Back") { vm.back() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ─── Step content router ──────────────────────────────────────────────────

    @ViewBuilder private var stepContent: some View {
        switch vm.currentStep {
        case .account:         stepAccountContent
        case .personal:        stepPersonalContent
        case .menstrual:       stepMenstrualContent
        case .body:            stepBodyContent
        case .goal:            stepGoalContent
        case .activity:        stepActivityContent
        case .occupation:      stepOccupationContent
        case .diet:            stepDietContent
        case .mealsWater:      stepMealsWaterContent
        case .sleep:           stepSleepContent
        case .stress:          stepStressContent
        case .screenTime:      stepScreenTimeContent
        case .habits:          stepHabitsContent
        case .smokingDetail:   stepSmokingDetailContent
        case .alcoholDetail:   stepAlcoholDetailContent
        case .familyHistory:   stepFamilyHistoryContent
        case .allergies:       stepAllergiesContent
        case .sunExposure:     stepSunExposureContent
        case .medical:         stepMedicalContent
        case .conditionDetail: stepConditionDetailContent
        case .ancestry:        stepAncestryContent
        }
    }

    // ─── Account ──────────────────────────────────────────────────────────────

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

    // ─── Personal ─────────────────────────────────────────────────────────────

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

    // ─── Menstrual (conditional) ──────────────────────────────────────────────

    @ViewBuilder private var stepMenstrualContent: some View {
        Text("This helps us personalise nutrition and insights around your cycle. All optional.")
            .font(.caption)
            .foregroundStyle(.secondary)

        sectionHeader("What's your cycle like?")
        SelectableCardGrid(options: vm.menstrualStatusOptions, selection: $vm.menstrualStatus)

        sectionHeader("Any common symptoms?")
        MultiSelectCardGrid(options: vm.menstrualSymptomOptions, selection: $vm.menstrualSymptoms)

        sectionHeader("Pregnancy status")
        SelectableCardGrid(options: vm.pregnancyOptions, selection: $vm.pregnancyStatus)

        sectionHeader("Average cycle length?")
        SelectableCardGrid(options: vm.cycleLengthOptions, selection: $vm.cycleLengthSel)

        sectionHeader("Typical period length?")
        SelectableCardGrid(options: vm.periodLengthOptions, selection: $vm.periodLengthSel)

        sectionHeader("Contraception method?")
        SelectableCardGrid(options: vm.contraceptionOptions,
                           selection: $vm.contraceptionMethod,
                           otherText: $vm.contraceptionOther)
    }

    // ─── Body ─────────────────────────────────────────────────────────────────

    @ViewBuilder private var stepBodyContent: some View {
        stepperRow(title: "Height",
                   value: "\(Int(vm.heightCm)) cm") {
            Stepper("", value: $vm.heightCm, in: 100...250, step: 1).labelsHidden()
        }

        stepperRow(title: "Weight",
                   value: String(format: "%.1f kg", vm.weightKg)) {
            Stepper("", value: $vm.weightKg, in: 30...250, step: 0.5).labelsHidden()
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Waist circumference (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(vm.waistUnknown ? "—" : "\(Int(vm.waistCircumferenceCm)) cm")
                    .font(.subheadline)
                Spacer()
                Stepper("", value: $vm.waistCircumferenceCm, in: 40...200, step: 1)
                    .labelsHidden()
                    .disabled(vm.waistUnknown)
                    .onChange(of: vm.waistCircumferenceCm) { _, _ in
                        // Interacting means the user does know their waist.
                        if vm.waistUnknown { vm.waistUnknown = false }
                    }
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
            Toggle("I don't know", isOn: $vm.waistUnknown)
                .font(.subheadline)
                .tint(Theme.brandTeal)
        }
    }

    // ─── Goal ─────────────────────────────────────────────────────────────────

    @ViewBuilder private var stepGoalContent: some View {
        sectionHeader("Pick what you want to focus on most")
        SelectableCardGrid(options: vm.goalOptions,
                           selection: $vm.primaryGoal,
                           otherText: $vm.primaryGoalOther)

        sectionHeader("Has your weight changed recently?")
        SelectableCardGrid(options: vm.recentWeightChangeOptions, selection: $vm.recentWeightChange)
    }

    // ─── Activity ─────────────────────────────────────────────────────────────

    @ViewBuilder private var stepActivityContent: some View {
        pickerField("Activity level") {
            Picker("Activity level", selection: $vm.activityLevel) {
                ForEach(1...5, id: \.self) { level in
                    Text(vm.activityOptions[level - 1]).tag(level)
                }
            }
        }
    }

    // ─── Occupation ───────────────────────────────────────────────────────────

    @ViewBuilder private var stepOccupationContent: some View {
        SelectableCardGrid(options: vm.occupationOptions,
                           selection: $vm.occupationType,
                           otherText: $vm.occupationOther)
    }

    // ─── Diet ─────────────────────────────────────────────────────────────────

    @ViewBuilder private var stepDietContent: some View {
        SelectableCardGrid(options: vm.dietOptions,
                           selection: $vm.dietType,
                           otherText: $vm.dietTypeOther)
    }

    // ─── Meals + Water ────────────────────────────────────────────────────────

    @ViewBuilder private var stepMealsWaterContent: some View {
        sectionHeader("How many meals a day?")
        SelectableCardGrid(options: vm.mealsOptions, selection: $vm.mealsPerDaySel)

        sectionHeader("How much water do you drink?")
        SelectableCardGrid(options: vm.waterOptions, selection: $vm.waterIntakeSel)
    }

    // ─── Sleep ────────────────────────────────────────────────────────────────

    @ViewBuilder private var stepSleepContent: some View {
        stepperRow(title: "Average sleep hours",
                   value: String(format: "%.1f hrs", vm.sleepHours)) {
            Stepper("", value: $vm.sleepHours, in: 3...12, step: 0.5).labelsHidden()
        }
    }

    // ─── Stress ───────────────────────────────────────────────────────────────

    @ViewBuilder private var stepStressContent: some View {
        SelectableCardGrid(options: vm.stressOptions, selection: $vm.stressSel)
    }

    // ─── Screen time ──────────────────────────────────────────────────────────

    @ViewBuilder private var stepScreenTimeContent: some View {
        SelectableCardGrid(options: vm.screenTimeOptions, selection: $vm.screenTimeBeforeBed, columns: 1)
    }

    // ─── Habits ───────────────────────────────────────────────────────────────

    @ViewBuilder private var stepHabitsContent: some View {
        Text("Honest answers help us give you genuinely better health advice.")
            .font(.caption)
            .foregroundStyle(.secondary)

        sectionHeader("Do you smoke?")
        SelectableCardGrid(options: vm.smokingOptions, selection: $vm.smokingStatus, columns: 1)

        sectionHeader("How often do you drink alcohol?")
        SelectableCardGrid(options: vm.alcoholOptions, selection: $vm.alcoholConsumption, columns: 1)

        sectionHeader("What's your daily fuel?")
        SelectableCardGrid(options: vm.caffeineOptions,
                           selection: $vm.caffeineHabit,
                           otherText: $vm.caffeineOther)
    }

    // ─── Smoking detail (conditional) ─────────────────────────────────────────

    @ViewBuilder private var stepSmokingDetailContent: some View {
        sectionHeader("How long have you smoked?")
        SelectableCardGrid(options: vm.smokingDurationOptions, selection: $vm.smokingDuration)

        sectionHeader("How many a day?")
        SelectableCardGrid(options: vm.cigarettesPerDayOptions, selection: $vm.cigarettesPerDay)

        sectionHeader("When did you last smoke?")
        SelectableCardGrid(options: vm.lastSmokedOptions, selection: $vm.lastSmoked)
    }

    // ─── Alcohol detail (conditional) ─────────────────────────────────────────

    @ViewBuilder private var stepAlcoholDetailContent: some View {
        sectionHeader("Drinks per week?")
        SelectableCardGrid(options: vm.drinksPerWeekOptions, selection: $vm.drinksPerWeek)
    }

    // ─── Family history ───────────────────────────────────────────────────────

    @ViewBuilder private var stepFamilyHistoryContent: some View {
        sectionHeader("Has anyone in your family had…")
        MultiSelectCardGrid(options: vm.familyHistoryOptions,
                            selection: $vm.familyHistory,
                            otherText: $vm.familyHistoryOther)

        sectionHeader("Who in your family?")
        MultiSelectCardGrid(options: vm.familyRelativeOptions, selection: $vm.familyHistoryRelatives)
    }

    // ─── Allergies ────────────────────────────────────────────────────────────

    @ViewBuilder private var stepAllergiesContent: some View {
        Text("Safety-critical — we'll cross-reference these with food checks and medication advice.")
            .font(.caption)
            .foregroundStyle(.secondary)
        MultiSelectCardGrid(options: vm.allergyOptions,
                            selection: $vm.allergies,
                            otherText: $vm.allergiesOther)
    }

    // ─── Sun exposure ─────────────────────────────────────────────────────────

    @ViewBuilder private var stepSunExposureContent: some View {
        SelectableCardGrid(options: vm.sunExposureOptions, selection: $vm.sunExposure, columns: 1)
    }

    // ─── Medical ──────────────────────────────────────────────────────────────

    @ViewBuilder private var stepMedicalContent: some View {
        Text("Optional — skip any section you prefer not to share.")
            .font(.caption)
            .foregroundStyle(.secondary)

        pickerField("Blood type (optional)") {
            Picker("Blood type", selection: $vm.bloodType) {
                Text("Don't know / skip").tag("")
                ForEach(vm.bloodTypeOptions, id: \.self) { Text($0).tag($0) }
            }
        }

        sectionHeader("Any medical conditions?")
        MultiSelectCardGrid(options: vm.conditionOptions,
                            selection: $vm.medicalConditions,
                            otherText: $vm.medicalConditionsOther)

        sectionHeader("Do you take any regular medications?")
        MultiSelectCardGrid(options: vm.medicationOptions,
                            selection: $vm.medicationCategories,
                            otherText: $vm.medicationOther)
    }

    // ─── Condition detail (conditional) ───────────────────────────────────────

    @ViewBuilder private var stepConditionDetailContent: some View {
        sectionHeader("When were you first diagnosed?")
        SelectableCardGrid(options: [
            .init("<1 year",    title: "Under a year"),
            .init("1-5 years",  title: "1–5 years"),
            .init("5-10 years", title: "5–10 years"),
            .init("10+ years",  title: "10+ years")
        ], selection: $vm.conditionsDiagnosed)

        sectionHeader("On medication for it?")
        SelectableCardGrid(options: [
            .init("Yes",  title: "Yes"),
            .init("Some", title: "Some"),
            .init("No",   title: "No")
        ], selection: $vm.conditionsMedicated, columns: 3)
    }

    // ─── Ancestry ─────────────────────────────────────────────────────────────

    @ViewBuilder private var stepAncestryContent: some View {
        Text("Risk for some conditions varies by ancestry — this sharpens our predictions.")
            .font(.caption)
            .foregroundStyle(.secondary)
        SelectableCardGrid(options: vm.ethnicityOptions, selection: $vm.ethnicity)
    }

    // ─── Step progress bars ────────────────────────────────────────────────────

    private var stepBars: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(0..<max(vm.totalSteps, 1)), id: \.self) { i in
                Capsule()
                    .fill(i <= vm.stepIndex ? Theme.brandTeal : Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: vm.stepIndex)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.m)
    }

    // ─── Step icon header ──────────────────────────────────────────────────────
    // Circular step icon + caption — driven by the current dynamic step.

    private var stepHeaderIcon: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle()
                    .fill(Theme.brandTeal.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: vm.currentStep.systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.brandTeal)
            }
            Text("Step \(vm.stepIndex + 1) of \(vm.totalSteps)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.brandTeal)
            Text(vm.currentStep.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity)
    }

    // ─── Reusable field helpers ────────────────────────────────────────────────

    /// Sub-section title inside a multi-question step card.
    @ViewBuilder private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.xs)
    }

    /// A labelled value row with a trailing stepper — used for height/weight/waist/sleep.
    @ViewBuilder private func stepperRow<Control: View>(
        title: String,
        value: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(value).font(.subheadline)
                Spacer()
                control()
            }
            .padding(Theme.Spacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.input))
        }
    }

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

#Preview {
    NavigationStack { SignupView() }
        .environment(AppEnvironment())
}
