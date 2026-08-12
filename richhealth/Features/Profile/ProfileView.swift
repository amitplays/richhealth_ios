import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.openURL) private var openURL
    @State private var vm = ProfileViewModel()
    @State private var selectedTab = 0
    @State private var showLogoutConfirm = false
    @State private var showCustomInstructionsEditor = false
    @State private var showLegal = false
    @State private var showRequests = false
    @State private var health = HealthKitManager.shared

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            List {
                // ── Header (no list chrome — GlassCard provides the surface) ──
                Section {
                    ProfileHeaderView(
                        user: appEnv.auth.currentUser,
                        proAccess: vm.proAccess,
                        isLoading: vm.isLoading,
                        aqiValue: vm.cachedAQI,
                        heartRate: health.latestHeartRate,
                        onFillProfile: {
                            vm.prepareEditForm(from: appEnv.auth.currentUser)
                            vm.showEditSheet = true
                        }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listSectionSpacing(0)

                // ── Segment picker ─────────────────────────────────────────────
                Section {
                    // Native segmented control — keeps the real Liquid Glass (native glass is required).
                    // ICON-ONLY variant (active):
                    Picker("Section", selection: $selectedTab) {
                        Image(systemName: "person.fill").tag(0)
                        Image(systemName: "gearshape.fill").tag(1)
                        Image(systemName: "crown.fill").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .padding(.horizontal, -16)
                    .tint(Theme.brandTeal)

                    // TEXT variant — to use this, uncomment below and comment out the icon-only Picker above.
                    // Picker("Section", selection: $selectedTab) {
                    //     Text("Profile").tag(0)
                    //     Text("Settings").tag(1)
                    //     Text("Plan").tag(2)
                    // }
                    // .pickerStyle(.segmented)
                    // .controlSize(.large)
                    // .padding(.horizontal, -16)
                    // .tint(Theme.brandTeal)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listSectionSpacing(0)

                // ── Tab content ────────────────────────────────────────────────
                if selectedTab == 0 {
                    profileContent(user: appEnv.auth.currentUser)
                } else if selectedTab == 1 {
                    settingsContent(vm: vm)
                } else {
                    planContent(vm: vm)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await vm.reload(auth: appEnv.auth) }
            .navigationTitle("Profile")
            .toolbar {
                // One "options" button → dropdown with Edit, Requests and Log Out.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            vm.prepareEditForm(from: appEnv.auth.currentUser)
                            vm.showEditSheet = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        Button {
                            showRequests = true
                        } label: {
                            Label(vm.pendingRequestCount > 0 ? "Requests (\(vm.pendingRequestCount))" : "Requests",
                                  systemImage: "person.2")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            // Red dot when there are pending requests, so they're discoverable.
                            .overlay(alignment: .topTrailing) {
                                if vm.pendingRequestCount > 0 {
                                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 4, y: -4)
                                }
                            }
                    }
                    .tint(Theme.brandTeal)
                }
            }
            .task { await vm.load(auth: appEnv.auth) }
            .task { await health.autoSyncIfNeeded() }
            .confirmationDialog("Log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Log out", role: .destructive) { appEnv.auth.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to access your health data.")
            }
            .sheet(isPresented: $showRequests) {
                FamilyRequestsSheet(onChanged: { Task { await vm.loadPendingRequests() } })
            }
            .sheet(isPresented: $vm.showEditSheet) { EditProfileSheet(vm: vm, auth: appEnv.auth) }
            .sheet(isPresented: $vm.showPaywall) { PaywallView() }
            .sheet(isPresented: $vm.showMemorySheet) { MemoryManagerSheet(vm: vm, auth: appEnv.auth) }
            .sheet(isPresented: $vm.showChangePassword) { ChangePasswordSheet(auth: appEnv.auth) }
            .sheet(isPresented: $showLegal) { LegalHubSheet() }
            .sheet(isPresented: $vm.showFullUsage) {
                if let usage = vm.usageData { UsageFullSheet(usage: usage) }
            }
            .sheet(isPresented: $showCustomInstructionsEditor) {
                CustomInstructionsEditorSheet(text: $vm.aiCustomInstructions)
            }
            .alert("Couldn't Save Preferences", isPresented: Binding(
                get: { vm.aiSaveError != nil },
                set: { if !$0 { vm.aiSaveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.aiSaveError ?? "")
            }
            .onAppear {
                // Selected segment: solid teal capsule + white text. Unselected: dim grey.
                UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.brandTeal)
                UISegmentedControl.appearance().setTitleTextAttributes(
                    [.foregroundColor: UIColor.white], for: .selected
                )
                UISegmentedControl.appearance().setTitleTextAttributes(
                    [.foregroundColor: UIColor.systemGray], for: .normal
                )
            }
            // Auto-save AI prefs when user leaves Settings tab (mirrors Android's persistAiPreferences on change)
            .onChange(of: selectedTab) { old, new in
                guard old == 1 else { return }
                Task { await vm.saveAIPreferences(auth: appEnv.auth) }
            }
            // Save when custom instructions editor closes
            .onChange(of: showCustomInstructionsEditor) { old, new in
                guard old == true, new == false else { return }
                Task { await vm.saveAIPreferences(auth: appEnv.auth) }
            }
        }
    }

    // MARK: - Profile tab

    @ViewBuilder private func profileContent(user: UserProfile?) -> some View {
        // Personal Info — mirrors Android "Personal Info" card (email, age, gender, phone, location, occupation, ancestry)
        Section("Personal Info") {
            if let email = user?.email, !email.isEmpty {
                ProfileInfoRow(icon: "envelope.fill", label: "Email", value: email)
            }
            if let age = user?.age {
                ProfileInfoRow(icon: "calendar", label: "Age", value: "\(age) years")
            }
            ProfileInfoRow(icon: "figure.stand", label: "Gender", value: user?.gender ?? "—")
            if let phone = user?.phoneNumber, !phone.isEmpty {
                ProfileInfoRow(icon: "phone.fill", label: "Phone", value: phone)
            }
            if let loc = user?.location, !loc.isEmpty {
                ProfileInfoRow(icon: "mappin.circle.fill", label: "Location", value: loc)
            }
            if let occ = user?.occupationType, !occ.isEmpty {
                ProfileInfoRow(icon: "briefcase.fill", label: "Occupation", value: occ)
            }
            if let eth = user?.ethnicity, !eth.isEmpty {
                ProfileInfoRow(icon: "globe.americas.fill", label: "Ancestry", value: eth)
            }
        }

        // Physical — mirrors Android "Health & Lifestyle" physical rows
        Section("Physical") {
            ProfileInfoRow(icon: "ruler", label: "Height",
                           value: user?.height.map { "\(Int($0)) cm" } ?? "—")
            ProfileInfoRow(icon: "scalemass.fill", label: "Weight",
                           value: user?.weight.map { String(format: "%.1f kg", $0) } ?? "—")
            if let wc = user?.waistCircumference, wc > 0 {
                ProfileInfoRow(icon: "figure.arms.open", label: "Waist", value: "\(Int(wc)) cm")
            }
            ProfileInfoRow(icon: "drop.fill", label: "Blood type", value: user?.bloodType ?? "—")
            if let rwc = user?.recentWeightChange, !rwc.isEmpty {
                ProfileInfoRow(icon: "arrow.up.arrow.down", label: "Recent weight change", value: rwc)
            }
        }

        // Fitness & Goals — mirrors Android "Fitness Goals" card
        Section("Fitness & Goals") {
            ProfileInfoRow(icon: "target", label: "Primary goal", value: user?.primaryGoal ?? "—")
            if let wg = user?.weeklyGoal, wg > 0 {
                ProfileInfoRow(icon: "figure.run", label: "Weekly goal", value: "\(wg)x / week")
            }
            ProfileInfoRow(icon: "bolt.fill", label: "Activity level",
                           value: user?.activityLevelLabel ?? "—")
            ProfileInfoRow(icon: "fork.knife", label: "Diet type", value: user?.dietType ?? "—")
        }

        // Lifestyle — mirrors Android "Lifestyle" card
        if let user, hasLifestyle(user) {
            Section("Lifestyle") { lifestyleRows(user: user) }
        }

        // Habits — mirrors Android "Habits" card
        if let user, hasHabits(user) {
            Section("Habits") { habitsRows(user: user) }
        }

        // Medical — conditions, allergies, medication types displayed as chips (mirrors Android chip groups)
        if let user, hasMedical(user) {
            Section("Medical") { medicalRows(user: user) }
        }

        // Family History — chip groups for history + affected relatives (mirrors Android "Family History" card)
        if let user, hasFamilyHistory(user) {
            Section("Family History") { familyHistoryRows(user: user) }
        }

        // Reproductive Health — conditional for female/other users
        if let user, user.showReproductiveHealth {
            Section("Reproductive Health") { reproRows(user: user) }
        }
    }

    private func hasLifestyle(_ u: UserProfile) -> Bool {
        u.sleepHours != nil || (u.waterIntake ?? 0) > 0 || (u.mealsPerDay ?? 0) > 0 ||
        u.stressLevel != nil || u.screenTimeLabel != nil || u.sunExposure != nil
    }
    private func hasHabits(_ u: UserProfile) -> Bool {
        u.smokingLabel != nil || u.alcoholConsumption != nil || u.caffeineLabel != nil
    }
    private func hasMedical(_ u: UserProfile) -> Bool {
        u.medicalConditions?.isEmpty == false ||
        u.allergies?.isEmpty == false ||
        u.medicationCategories?.isEmpty == false
    }
    private func hasFamilyHistory(_ u: UserProfile) -> Bool {
        u.familyHistory?.isEmpty == false || u.familyHistoryRelatives?.isEmpty == false
    }

    @ViewBuilder private func lifestyleRows(user: UserProfile) -> some View {
        if let s = user.sleepHours {
            ProfileInfoRow(icon: "moon.fill", label: "Sleep",
                           value: String(format: "%.1f hrs/night", s))
        }
        if let w = user.waterIntake, w > 0 {
            ProfileInfoRow(icon: "drop.circle.fill", label: "Water intake", value: "\(w) glasses/day")
        }
        if let m = user.mealsPerDay, m > 0 {
            ProfileInfoRow(icon: "fork.knife.circle.fill", label: "Meals/day", value: "\(m)")
        }
        if let label = user.stressLabel {
            ProfileInfoRow(icon: "brain.head.profile", label: "Stress", value: label)
        }
        if let label = user.screenTimeLabel {
            ProfileInfoRow(icon: "iphone", label: "Screen at night", value: label)
        }
        if let sun = user.sunExposure {
            let label: String = {
                switch sun {
                case "low":      return "Mostly indoors"
                case "moderate": return "Some outdoor time"
                case "high":     return "Mostly outdoors"
                default:         return sun
                }
            }()
            ProfileInfoRow(icon: "sun.max.fill", label: "Sun exposure", value: label)
        }
    }

    @ViewBuilder private func habitsRows(user: UserProfile) -> some View {
        if let label = user.smokingLabel {
            ProfileInfoRow(icon: "wind", label: "Smoking", value: label)
        }
        if let a = user.alcoholConsumption {
            ProfileInfoRow(icon: "wineglass.fill", label: "Alcohol", value: a)
        }
        if let label = user.caffeineLabel {
            ProfileInfoRow(icon: "cup.and.saucer.fill", label: "Caffeine", value: label)
        }
    }

    @ViewBuilder private func medicalRows(user: UserProfile) -> some View {
        if let items = user.medicalConditions, !items.isEmpty {
            ProfileChipsRow(icon: "cross.case.fill", label: "Conditions", items: items)
        }
        if let items = user.allergies, !items.isEmpty {
            ProfileChipsRow(icon: "allergens", label: "Allergies", items: items)
        }
        if let items = user.medicationCategories, !items.isEmpty {
            ProfileChipsRow(icon: "pills.fill", label: "Medication types", items: items)
        }
    }

    @ViewBuilder private func familyHistoryRows(user: UserProfile) -> some View {
        if let items = user.familyHistory, !items.isEmpty {
            ProfileChipsRow(icon: "person.2.fill", label: "Conditions in family", items: items)
        }
        if let items = user.familyHistoryRelatives, !items.isEmpty {
            ProfileChipsRow(icon: "person.3.fill", label: "Affected relatives", items: items)
        }
    }

    @ViewBuilder private func reproRows(user: UserProfile) -> some View {
        if let label = user.menstrualStatusLabel {
            ProfileInfoRow(icon: "waveform.path.ecg", label: "Cycle", value: label)
        }
        if let p = user.pregnancyStatus, p != "not_applicable" {
            let label: String = {
                switch p {
                case "not_pregnant":       return "Not pregnant"
                case "pregnant":           return "Pregnant"
                case "postpartum":         return "Postpartum"
                case "trying_to_conceive": return "Trying to conceive"
                default:                   return p
                }
            }()
            ProfileInfoRow(icon: "heart.circle.fill", label: "Pregnancy status", value: label)
        }
        if let cl = user.averageCycleLength, cl > 0 {
            ProfileInfoRow(icon: "arrow.triangle.2.circlepath", label: "Avg cycle length",
                           value: "\(cl) days")
        }
        if let pl = user.averagePeriodLength, pl > 0 {
            ProfileInfoRow(icon: "calendar.badge.clock", label: "Period length",
                           value: "\(pl) days")
        }
        if let c = user.contraceptionMethod, !c.isEmpty {
            ProfileInfoRow(icon: "shield.fill", label: "Contraception", value: c)
        }
        if let items = user.menstrualSymptoms, !items.isEmpty {
            ProfileChipsRow(icon: "list.bullet", label: "Cycle symptoms", items: items)
        }
    }

    // MARK: - Settings tab
    // All rows use the identical HStack pattern: icon(15pt/22pt) | label text | Spacer | control
    // No Label { } icon: { } wrappers — those go through Toggle/Picker's own rendering pipeline
    // and produce different visual sizes than plain HStack rows.

    @ViewBuilder private func settingsContent(vm: ProfileViewModel) -> some View {
        @Bindable var vm = vm

        Section("AI & Chat") {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Response tone")
                Spacer()
                Picker("", selection: $vm.aiTone) {
                    Text("Balanced").tag("balanced")
                    Text("Warm").tag("warm")
                    Text("Direct").tag("direct")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.secondary)
            }
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Reply length")
                Spacer()
                Picker("", selection: $vm.aiReplyLength) {
                    Text("Concise").tag("concise")
                    Text("Balanced").tag("balanced")
                    Text("Detailed").tag("detailed")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.secondary)
            }
            Button {
                showCustomInstructionsEditor = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Custom instructions")
                        Text(vm.aiCustomInstructions.isEmpty ? "Add instructions for Richie…" : vm.aiCustomInstructions)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "rectangle.badge.checkmark")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Quick-log cards")
                Spacer()
                Toggle("", isOn: $vm.aiAutofillCards).labelsHidden().tint(Theme.brandTeal)
            }
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "bookmark")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Save conversation memories")
                Spacer()
                Toggle("", isOn: $vm.aiSaveMemories).labelsHidden().tint(Theme.brandTeal)
            }
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "cpu")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Show AI thinking")
                Spacer()
                Toggle("", isOn: $vm.aiShowThinking).labelsHidden().tint(Theme.brandTeal)
            }
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "star")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Help improve the AI model")
                Spacer()
                Toggle("", isOn: $vm.aiImproveModel).labelsHidden().tint(Theme.brandTeal)
            }
            Button {
                vm.showMemorySheet = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "brain")
                        .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                    Text("AI Memory")
                    Spacer()
                    if !vm.memories.isEmpty {
                        Text("\(vm.memories.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }

        Section("General") {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Notifications")
                Spacer()
                Toggle("", isOn: $vm.notificationsEnabled).labelsHidden().tint(Theme.brandTeal)
            }
            .onChange(of: vm.notificationsEnabled) { _, enabled in
                // Use the plan already loaded by vm.load — NO network call from a local toggle.
                let tier = vm.proAccess?.tier ?? "free"
                Task {
                    let ok = await LocalNotificationManager.shared.setEnabled(enabled, tier: tier)
                    // Turned on but denied at the OS level → revert the toggle.
                    if enabled && !ok { vm.notificationsEnabled = false }
                }
            }
            Button {
                if let url = URL(string: "App-Prefs:NOTIFICATIONS_ID") { openURL(url) }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22, alignment: .center)
                    Text("Open iOS notification settings")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "ruler")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Metric units (cm / kg)")
                Spacer()
                Toggle("", isOn: $vm.isMetric).labelsHidden().tint(Theme.brandTeal)
            }
        }

        Section("Security & Privacy") {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "faceid")
                    .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                Text("Biometric lock")
                Spacer()
                Toggle("", isOn: $vm.biometricEnabled).labelsHidden().tint(Theme.brandTeal)
            }
            .disabled(!appEnv.biometric.canDeviceAuthenticate)
            .onChange(of: vm.biometricEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    let ok = await appEnv.biometric.verifyForSetup()
                    if !ok { vm.biometricEnabled = false }
                }
            }
            Button {
                vm.showChangePassword = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                    Text("Change password")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            if let user = appEnv.auth.currentUser {
                ShareLink(item: progressShareText(user: user)) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                        Text("Share progress")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }

        Section("About") {
            Button {
                showLegal = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15)).foregroundStyle(Theme.brandTeal).frame(width: 22, alignment: .center)
                    Text("Legal & Privacy")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func progressShareText(user: UserProfile) -> String {
        var lines = ["My RichHealth stats:"]
        if let w = user.weight { lines.append("Weight: \(String(format: "%.1f", w)) kg") }
        if let h = user.height { lines.append("Height: \(Int(h)) cm") }
        if let s = user.sleepHours { lines.append("Sleep: \(String(format: "%.1f", s)) hrs/night") }
        if let w = user.waterIntake { lines.append("Daily water: \(w) glasses") }
        if let g = user.primaryGoal, !g.isEmpty { lines.append("Goal: \(g)") }
        lines.append("Shared via RichHealth")
        return lines.joined(separator: "\n")
    }

    // MARK: - Plan tab

    @ViewBuilder private func planContent(vm: ProfileViewModel) -> some View {
        if let access = vm.proAccess {
            Section("Your Plan") {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(access.displayName).font(.headline)
                        if let expiry = access.expiryDate {
                            Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if access.isPro {
                            Text("All features unlocked")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Upgrade to unlock all features")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusPill(text: access.isPro ? "Pro" : "Free")
                }
                if !access.isPro {
                    Button("Upgrade to Pro") { vm.showPaywall = true }
                        .foregroundStyle(Theme.brandTeal)
                }
            }
        } else {
            Section("Your Plan") {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("Loading plan…").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }

        if let usage = vm.usageData {
            Section("This Month") {
                Button {
                    vm.showFullUsage = true
                } label: {
                    HStack {
                        Label("View full usage", systemImage: "chart.bar.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(Theme.brandTeal)

                // Full-width rows — §18: text-heavy usage data belongs in list rows, not grids
                if let e = usage.usage.chatSessions    { UsageRingItem(label: "Chat sessions",    entry: e) }
                if let e = usage.usage.medicalReports  { UsageRingItem(label: "Medical reports",  entry: e) }
                if let e = usage.usage.reportAnalysis  { UsageRingItem(label: "Report analysis",  entry: e) }
                if let e = usage.usage.nutricheck      { UsageRingItem(label: "NutriCheck",        entry: e) }
                if let e = usage.usage.healthAnalysis  { UsageRingItem(label: "Health analysis",  entry: e) }
                // Dietary insights hidden for now (product decision).
            }
        }

        // MEMBERSHIP — mirrors Android Plan tab Membership section (subscription + family rows)
        if vm.proAccess != nil {
            Section("Membership") {
                // Subscription summary row — ic_premium (crown) + "Subscription" + subtitle
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Theme.brandTeal)
                        .frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Subscription").font(.subheadline)
                        Text(membershipSubtitle(vm.proAccess))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }

                // Family management rows — owners only (matches Android membership_family_section)
                if vm.isFamilyPlanOwner {
                    // Family header row: family icon + "Family Members" + "N/5 covered" count in teal
                    // Count is a data label (§7), not a status signal — use Text, not StatusPill
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(Theme.brandTeal)
                            .frame(width: 22, alignment: .center)
                        Text("Family Members").font(.subheadline)
                        Spacer()
                        Text("\(vm.familyProMemberCount)/\(vm.maxFamilyMembers) covered")
                            .font(.caption.bold()).foregroundStyle(Theme.brandTeal)
                    }

                    if vm.relationships.isEmpty {
                        HStack(spacing: Theme.Spacing.s) {
                            Spacer().frame(width: 22)
                            Text("No connected relatives yet. Connect family from Health Hub.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(vm.relationships) { member in
                        PlanMemberRow(member: member, canRemove: true) { uid in
                            Task { await vm.removeFamilyMember(userId: uid) }
                        }
                    }
                }
            }
        }
    }

    // Subscription subtitle — matches Android's dynamic subtitle logic in ProfileFragment
    private func membershipSubtitle(_ proAccess: ProAccess?) -> String {
        guard let access = proAccess else { return "Free plan" }
        if access.tier == "family_member" { return "Pro shared via family plan" }
        if !access.isPro { return "Free plan · Upgrade for more" }
        if let expiry = access.expiryDate {
            return "\(access.displayName) · Active until \(expiry.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(access.displayName) · Active"
    }
}

// MARK: - Plan Member Row

/// Single family member row in the Plan tab Membership section.
/// Mirrors item_plan_family_member.xml: teal person icon | name + inline badges | meta | Remove button.
private struct PlanMemberRow: View {
    let member: RelationshipRecord
    let canRemove: Bool
    let onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            // Teal person icon — matches Android ic_person with rh_accent tint (20dp)
            Image(systemName: "person.fill")
                .foregroundStyle(Theme.brandTeal)
                .font(.system(size: 18))
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Name + inline COVERED/PRO badges (matches Android name row)
                HStack(spacing: 6) {
                    Text(member.name ?? member.email ?? "Unknown")
                        .font(.subheadline).lineLimit(1)
                    if member.isCoveredByMyPlan == true {
                        StatusPill(text: "Covered", level: .green)
                    } else if member.isPro == true {
                        // "Pro" is a plan badge (§12) — no level, defaults to brand teal
                        StatusPill(text: "Pro")
                    }
                }
                // Row 2: "Relation · email" meta (matches Android meta row)
                let meta = memberMeta
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            // Remove button — outlined, compact, red (matches Android TextButton with red stroke)
            if canRemove, let uid = member.userId {
                Button("Remove") { onRemove(uid) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)  // destructive action
            }
        }
    }

    private var memberMeta: String {
        let parts = [member.relationship, member.email].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Header

private struct ProfileHeaderView: View {
    let user: UserProfile?
    let proAccess: ProAccess?
    let isLoading: Bool
    let aqiValue: Int?
    var heartRate: Int? = nil
    var onFillProfile: (() -> Void)? = nil

    var body: some View {
        let completionFraction = user?.completionPercent ?? 0

        GlassCard {
                VStack(spacing: Theme.Spacing.m) {
                    // Identity row — mirrors Android fragment_profile.xml header.
                    HStack(spacing: Theme.Spacing.m) {
                        // Completion arc sits around the avatar — inside the card's padding,
                        // fully immune to the List insetGrouped section clip that broke the card-edge approach.
                        ZStack {
                            Text(initials(user?.name))
                                .font(.title2.bold())
                                .foregroundStyle(Theme.brandTeal)
                                .frame(width: 58, height: 58)
                                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                                .skeleton(isActive: isLoading)

                            if !isLoading, completionFraction > 0, completionFraction < 1.0 {
                                RoundedRectangle(cornerRadius: 22)
                                    .trim(from: 0, to: completionFraction)
                                    .stroke(
                                        Theme.brandTeal.opacity(0.7),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .frame(width: 70, height: 70)
                                    .rotationEffect(.degrees(-90))
                                    .allowsHitTesting(false)
                            }
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(user?.name ?? "—")
                                .font(.headline)
                                .skeleton(isActive: isLoading)
                            if let email = user?.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            // Plan pill intentionally removed from the header — the plan lives on
                            // the "Your Plan" card only (see §12: plan badges aren't status signals).
                            if user?.emailVerified == true {
                                StatusPill(text: "Verified", level: .green)
                            }
                        }
                        Spacer()
                    }

                    // "At a Glance" stats — Heart Rate | Air Quality | Weight | Sleep.
                    // Heart Rate (from Apple Watch/HealthKit) is the headline metric.
                    if !isLoading {
                        Divider()
                        HStack(spacing: 0) {
                            statColumn(label: "Heart Rate",
                                       value: heartRate.map { "\($0) bpm" } ?? "—",
                                       icon: "heart.fill")
                            Divider().frame(height: 36)
                            statColumn(label: "Air Quality",
                                       value: aqiValue.map { "\($0)" } ?? "—",
                                       icon: "aqi.medium")
                            Divider().frame(height: 36)
                            statColumn(label: "Weight",
                                       value: user?.weight.map { String(format: "%.0f kg", $0) } ?? "—",
                                       icon: "scalemass")
                            Divider().frame(height: 36)
                            statColumn(label: "Sleep",
                                       value: user?.sleepHours.map { String(format: "%.0f hrs", $0) } ?? "—",
                                       icon: "moon.fill")
                        }

                        // Completion CTA — only when profile is incomplete.
                        // The % is shown as the card's border trim, this row links to the edit sheet.
                        if completionFraction < 1.0, let fn = onFillProfile {
                            Divider()
                            Button(action: fn) {
                                HStack(spacing: Theme.Spacing.s) {
                                    Text("\(Int(completionFraction * 100))% complete")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.brandTeal)
                                    Spacer()
                                    Text("Add missing info")
                                        .font(.caption)
                                        .foregroundStyle(Theme.brandTeal)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.brandTeal)
                                }
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func statColumn(label: String, value: String, icon: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.brandTeal)
            Text(value)
                .font(.system(size: 15, weight: .medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "?" }
        return String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }
}

// MARK: - Info row

private struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.brandTeal)
                .frame(width: 22, alignment: .center)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Chip / tag display

/// Minimal wrapping flow layout using the Layout protocol (iOS 16+).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } +
            CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (subview, size) in row.items {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(LayoutSubview, CGSize)] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var lineX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : lineX + spacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
                lineX = 0
            }
            current.items.append((subview, size))
            current.height = max(current.height, size.height)
            lineX = current.items.count == 1 ? size.width : lineX + spacing + size.width
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Row with an icon + label followed by a wrapping chip group — mirrors Android ChipGroup pattern.
private struct ProfileChipsRow: View {
    let icon: String
    let label: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.brandTeal)
                    .frame(width: 22, alignment: .center)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .foregroundStyle(Theme.brandTeal)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }
}

// MARK: - Usage ring item

// Inline list row used in Plan tab — no ring (consistent with other settings rows)
private struct UsageRingItem: View {
    let label: String
    let entry: UserUsageResponse.Entry

    private var level: StatusLevel {
        if entry.limitReached { return .red }
        if entry.fraction >= 0.85 { return .orange }
        if entry.fraction >= 0.65 { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                Text(entry.displayText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.limitReached {
                StatusPill(text: "Limit", level: .red)
            } else if entry.fraction > 0 {
                // Numeric usage is a measurement, not a status signal — use Text (§C7)
                Text("\(Int(min(entry.fraction, 1.0) * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(level.color)
            }
        }
    }
}

// MARK: - Full usage sheet (mirrors Android UsageBottomSheet / UsageStatusActivity)

private struct UsageFullSheet: View {
    let usage: UserUsageResponse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.s) {
                    if let e = usage.usage.chatSessions    { UsageFullRow(label: "Chat sessions",    entry: e) }
                    if let e = usage.usage.medicalReports  { UsageFullRow(label: "Medical reports",  entry: e) }
                    if let e = usage.usage.reportAnalysis  { UsageFullRow(label: "Report analysis",  entry: e) }
                    if let e = usage.usage.nutricheck      { UsageFullRow(label: "NutriCheck",        entry: e) }
                    if let e = usage.usage.healthAnalysis  { UsageFullRow(label: "Health analysis",  entry: e) }
                    // Dietary insights hidden for now (product decision).
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// Card-style usage row — completion % shown as a border trim (same design language as ProfileHeaderView)
private struct UsageFullRow: View {
    let label: String
    let entry: UserUsageResponse.Entry

    private var usageLevel: StatusLevel {
        if entry.limitReached || entry.fraction >= 1.0 { return .red }
        if entry.fraction >= 0.85 { return .orange }
        if entry.fraction >= 0.65 { return .yellow }
        return .green
    }

    var body: some View {
        let fraction = min(entry.fraction, 1.0)
        GlassCard {
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label).font(.subheadline.weight(.semibold))
                        Text(entry.displayText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.limitReached {
                        StatusPill(text: "Limit reached", level: .red)
                    } else if fraction > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(fraction * 100))%")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(usageLevel.color)
                            Text("used")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                // Linear progress bar — clearer and more reliable than RoundedRectangle.trim
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 4)
                        Capsule()
                            .fill(usageLevel.color.opacity(0.85))
                            .frame(width: geo.size.width * fraction, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

// MARK: - AI Memory manager sheet (mirrors Android AI Memory dialog)

private struct MemoryManagerSheet: View {
    var vm: ProfileViewModel
    let auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingMemories {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.memories.isEmpty {
                    ContentUnavailableView(
                        "No Memories",
                        systemImage: "brain",
                        description: Text("Richie hasn't remembered anything about you yet.")
                    )
                } else {
                    List {
                        ForEach(vm.memories) { memory in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.fact).font(.subheadline)
                                if let cat = memory.category, !cat.isEmpty {
                                    Text(cat.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                let id = vm.memories[i].id
                                Task { await vm.deleteMemory(id: id, auth: auth) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.loadMemories(auth: auth) }
    }
}

// MARK: - Change password sheet

private struct ChangePasswordSheet: View {
    let auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var canSave: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                    SecureField("New password (min. 8 characters)", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption) // error feedback
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving { ProgressView() }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave).bold()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.changePassword(current: currentPassword, new: newPassword)
            dismiss()
        } catch let err as APIError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Couldn't change password. Please try again."
        }
    }
}

// MARK: - Edit profile sheet

private struct EditProfileSheet: View {
    @Bindable var vm: ProfileViewModel
    let auth: AuthManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $vm.editName)
                    TextField("Email", text: $vm.editEmail)
                        .keyboardType(.emailAddress).autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $vm.editPhone).keyboardType(.phonePad)
                }
                Section("Personal") {
                    Picker("Gender", selection: $vm.editGender) {
                        Text("Not set").tag("")
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                        Text("Other").tag("Other")
                    }
                    Toggle("Set date of birth", isOn: $vm.editDOBEnabled)
                    if vm.editDOBEnabled {
                        DatePicker("Date of birth", selection: $vm.editDOB,
                                   in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                    TextField("Location (city, country)", text: $vm.editLocation).autocorrectionDisabled()
                    TextField("Ethnicity (optional)", text: $vm.editEthnicity)
                }
                Section("Physical") {
                    HStack {
                        Text("Height (cm)")
                        Spacer()
                        TextField("0", value: $vm.editHeight, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("0", value: $vm.editWeight, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Waist (cm)")
                        Spacer()
                        TextField("0", value: $vm.editWaist, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    Picker("Blood type", selection: $vm.editBloodType) {
                        Text("Not set").tag("")
                        ForEach(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
                Section("Fitness") {
                    Picker("Primary goal", selection: $vm.editGoal) {
                        Text("Not set").tag("")
                        ForEach(["Improve Fitness", "Weight Loss", "Muscle Gain",
                                 "Manage a Health Condition", "Boost Energy",
                                 "Improve Sleep", "Eat Healthier", "Improve Mental Health"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    Picker("Activity level", selection: $vm.editActivityLevel) {
                        Text("Mostly Sitting").tag(1); Text("Light Activity").tag(2)
                        Text("Moderately Active").tag(3); Text("Very Active").tag(4)
                        Text("Athlete").tag(5)
                    }
                    Picker("Diet type", selection: $vm.editDietType) {
                        Text("Not set").tag("")
                        ForEach(["No Preference", "Regular", "Vegetarian", "Vegan",
                                 "Keto", "Mediterranean", "Gluten-Free"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
                Section("Medical") {
                    TextField("Conditions (comma-separated)",
                              text: $vm.editConditions, axis: .vertical).lineLimit(2...4)
                    TextField("Allergies (comma-separated)",
                              text: $vm.editAllergies, axis: .vertical).lineLimit(2...4)
                    TextField("Family history (comma-separated)",
                              text: $vm.editFamilyHistory, axis: .vertical).lineLimit(2...4)
                }
                Section("Lifestyle") {
                    HStack {
                        Text("Sleep hours")
                        Spacer()
                        Text(String(format: "%.1f h", vm.editSleepHours)).foregroundStyle(.secondary)
                        Stepper("", value: $vm.editSleepHours, in: 3...12, step: 0.5).labelsHidden()
                    }
                    HStack {
                        Text("Water (glasses/day)")
                        Spacer()
                        Text("\(vm.editWaterIntake)").foregroundStyle(.secondary)
                        Stepper("", value: $vm.editWaterIntake, in: 1...20).labelsHidden()
                    }
                    HStack {
                        Text("Meals per day")
                        Spacer()
                        Text("\(vm.editMealsPerDay)").foregroundStyle(.secondary)
                        Stepper("", value: $vm.editMealsPerDay, in: 1...8).labelsHidden()
                    }
                    Picker("Stress level", selection: $vm.editStressLevel) {
                        ForEach(vm.stressOptions, id: \.0) { Text($1).tag($0) }
                    }
                    Picker("Screen time before bed", selection: $vm.editScreenTime) {
                        ForEach(vm.screenTimeOptions, id: \.1) { Text($0).tag($1) }
                    }
                    Picker("Sun exposure", selection: $vm.editSunExposure) {
                        ForEach(vm.sunOptions, id: \.1) { Text($0).tag($1) }
                    }
                    TextField("Occupation type (optional)", text: $vm.editOccupationType)
                }
                Section("Habits") {
                    Picker("Smoking", selection: $vm.editSmokingStatus) {
                        ForEach(vm.smokingOptions, id: \.1) { Text($0).tag($1) }
                    }
                    Picker("Alcohol", selection: $vm.editAlcohol) {
                        ForEach(vm.alcoholOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Caffeine", selection: $vm.editCaffeine) {
                        ForEach(vm.caffeineOptions, id: \.1) { Text($0).tag($1) }
                    }
                }
                if vm.editGender == "Female" || vm.editGender == "Other" ||
                    !vm.editMenstrualStatus.isEmpty {
                    Section("Reproductive Health") {
                        Picker("Menstrual cycle", selection: $vm.editMenstrualStatus) {
                            ForEach(vm.menstrualStatusOptions, id: \.1) { Text($0).tag($1) }
                        }
                        Picker("Pregnancy status", selection: $vm.editPregnancyStatus) {
                            ForEach(vm.pregnancyStatusOptions, id: \.1) { Text($0).tag($1) }
                        }
                        if vm.editMenstrualStatus != "" &&
                            vm.editMenstrualStatus != "not_applicable" &&
                            vm.editMenstrualStatus != "prefer_not_to_say" {
                            HStack {
                                Text("Avg cycle (days)")
                                Spacer()
                                Text("\(vm.editCycleLength)").foregroundStyle(.secondary)
                                Stepper("", value: $vm.editCycleLength, in: 15...60).labelsHidden()
                            }
                            HStack {
                                Text("Period length (days)")
                                Spacer()
                                Text("\(vm.editPeriodLength)").foregroundStyle(.secondary)
                                Stepper("", value: $vm.editPeriodLength, in: 1...14).labelsHidden()
                            }
                        }
                        TextField("Contraception (optional)", text: $vm.editContraception)
                        TextField("Menstrual symptoms (comma-separated)",
                                  text: $vm.editMenstrualSymptoms, axis: .vertical).lineLimit(1...3)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { vm.showEditSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await vm.saveProfile(auth: auth) }
                    }
                    .bold()
                    .disabled(vm.isSaving)
                }
            }
            // Branded loader shown INSIDE the sheet during save (the global one is occluded behind it).
            .overlay {
                if vm.isSaving {
                    BrandedLoaderView(message: "Saving your profile…")
                }
            }
            .alert("Couldn't Save Profile", isPresented: Binding(
                get: { vm.saveError != nil },
                set: { if !$0 { vm.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.saveError ?? "")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Custom Instructions editor sheet

private struct CustomInstructionsEditorSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DarkRoundedTextEditor(
                text: $text,
                placeholder: "Tell Richie how to respond — tone, focus, things to avoid…",
                minHeight: 200
            )
            .padding(Theme.Spacing.m)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Custom Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ProfileView().environment(AppEnvironment())
}
