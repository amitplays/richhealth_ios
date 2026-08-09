import SwiftUI
import Charts

/// The "Services" tab — replaces Android HomeFragment (4 636 lines of Java).
/// Cards: briefing, daily advisory, AQI, dietary insights, health feed, workouts, doctor.
struct ServicesHomeView: View {
    @State private var vm = ServicesHomeViewModel()
    @State private var showCheckInSheet = false
    @State private var showWatchSheet = false
    @State private var health = HealthKitManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.cardPadding) {

                    // 1 — Daily Briefing (horizontal card strip)
                    if vm.isLoadingBriefing || !vm.briefingCards.isEmpty {
                        BriefingSectionView(cards: vm.briefingCards,
                                            source: vm.briefingSource,
                                            generatedAt: vm.briefingGeneratedAt,
                                            isLoading: vm.isLoadingBriefing)
                    }

                    // 2 — Health Analysis (status chip + headline)
                    HealthAnalysisCardView(
                        analysis: vm.healthAnalysis,
                        isLoading: vm.isLoadingAnalysis,
                        isGenerating: vm.isGeneratingAnalysis,
                        onView: { vm.activeSheet = .healthAnalysis },
                        onGenerate: { Task { await vm.generateAnalysis() } }
                    )

                    // 3 — Connect a device (Apple Health / Apple Watch) — native replacement
                    // for Android HomeFragment's Google Fit "Connect a Device" card.
                    DeviceSyncCardView(isConnected: health.isConnected,
                                       heartRate: health.latestHeartRate,
                                       heartRateAt: health.latestHeartRateAt,
                                       lastSyncTS: health.lastSyncTS) { showWatchSheet = true }

                    // 4 — Daily Check-In
                    if let checkIn = vm.checkIn {
                        CheckInCardView(checkIn: checkIn, onTap: { showCheckInSheet = true })
                    } else if vm.isLoadingCheckIn {
                        CheckInCardView(checkIn: nil, onTap: {})
                    }

                    // 4 — Daily Advisory (digest)
                    DigestCardView(digest: vm.digest, isLoading: vm.isLoadingDigest)

                    // 5 — AQI
                    AQICardView(aqiData: vm.aqiData, aqiHistory: vm.aqiHistory,
                                city: vm.locationCity, status: vm.aqiStatus)

                    // 6 — Dietary Insights
                    DietaryInsightsCardView(
                        insights: vm.dietaryInsights,
                        isLoading: vm.isLoadingDietary
                    )

                    // 6b — NutriCheck — its own feature (Android parity), not part of Dietary Insights
                    NutriCheckCardView(onTap: { vm.activeSheet = .nutriCheck })

                    // 7 — Feed preview (first 3 items + See All)
                    FeedPreviewSectionView(
                        items: Array(vm.feedItems.prefix(3)),
                        isLoading: vm.isLoadingFeed,
                        onSeeAll: { vm.activeSheet = .feed }
                    )

                    // 8 — Workouts
                    WorkoutsCardView(
                        workouts: vm.workouts,
                        isLoading: vm.isLoadingWorkouts,
                        onSeeAll: { vm.activeSheet = .workouts }
                    )

                    // 9 — Doctor connections
                    DoctorSectionView(
                        connected: vm.connectedDoctors,
                        incoming: vm.incomingDoctorRequests,
                        isLoading: vm.isLoadingDoctors,
                        onManage: { vm.activeSheet = .doctor },
                        onRespond: { email, accept in
                            Task { await vm.respondToDoctor(email: email, accept: accept) }
                        }
                    )
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.m)
            }
            .navigationTitle("Services")
            .refreshable { await vm.reload() }
        }
        .task { await vm.load() }
        .task { await vm.loadAQI() }
        .task { await health.autoSyncIfNeeded() }
        .sheet(item: $vm.activeSheet) { sheet in
            switch sheet {
            case .nutriCheck:     NutriCheckSheetView()
            case .feed:           FeedSheetView()
            case .workouts:       WorkoutSheetView()
            case .doctor:         DoctorSheetView()
            case .healthAnalysis: HealthAnalysisSheetView(analysis: vm.healthAnalysis)
            }
        }
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
        .sheet(isPresented: $showCheckInSheet) {
            CheckInSheetView()
        }
        .sheet(isPresented: $showWatchSheet) { WatchSyncSheetView() }
    }
}

// MARK: - Briefing section

private struct BriefingSectionView: View {
    let cards: [BriefingCard]
    let source: String?
    let generatedAt: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label("Your Briefing", systemImage: "sparkles")
                    .font(.headline)
                if isLoading { InlineLoader() }
                if source == "fresh" {
                    StatusPill(text: "Fresh")
                }
                Spacer()
                if let t = relativeTime(generatedAt) {
                    Text(t)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)

            if isLoading && cards.isEmpty {
                // Skeleton placeholder cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(0..<2, id: \.self) { _ in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Loading briefing…")
                                    Text("Placeholder point one here")
                                    Text("Placeholder point two here")
                                }
                                .frame(width: 260)
                            }
                            .skeleton(isActive: true)
                        }
                    }
                }
            } else if cards.isEmpty {
                GlassCard {
                    ContentUnavailableView(
                        "No Briefing Yet",
                        systemImage: "sparkles",
                        description: Text("Add health data to receive a personalized briefing.")
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(cards) { card in
                            BriefingCardItemView(card: card)
                                .frame(width: 280)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

private struct BriefingCardItemView: View {
    let card: BriefingCard

    var body: some View {
        StandardCard(
            title: card.title,
            titleFont: .subheadline.weight(.semibold),
            titleColor: Theme.brandTeal,
            statusText: card.priority.capitalized,
            statusLevel: card.statusLevel,
            bodyView: AnyView(
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(card.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                            Text("•").foregroundStyle(.secondary)
                            Text(point)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            )
        )
    }
}

// MARK: - Health Analysis card

private struct HealthAnalysisCardView: View {
    let analysis: HealthAnalysis?
    let isLoading: Bool
    let isGenerating: Bool
    let onView: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        StandardCard(
            icon: "waveform.path.ecg.rectangle",
            title: "Health Analysis",
            titleColor: Theme.brandTeal,
            statusText: isGenerating ? nil : analysis?.healthAnalysisStatus?.displayLabel,
            statusLevel: isGenerating ? nil : analysis?.healthAnalysisStatus?.statusLevel,
            bodyText: bodyLine,
            bodyLineLimit: 2,
            bodyView: bodyOverflow,
            // Data-changed badge
            warning: (!isGenerating && analysis?.dataChangesSinceAnalysis?.hasChanges == true)
                     ? "New data — refresh for updated insights" : nil,
            ctaTitle: (analysis != nil && !isGenerating) ? "View Full Analysis" : nil,
            ctaAction: onView,
            footerView: footerOverflow,
            date: (analysis != nil && !isGenerating) ? analysis.flatMap { relativeTime($0.lastUpdated) } : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if analysis != nil { onView() } }
    }

    private var bodyLine: String? {
        if isGenerating { return nil }
        if let a = analysis { return (a.headline?.isEmpty == false) ? a.headline : nil }
        if isLoading { return "Loading your health analysis…" }
        return "Generate your first AI-powered health analysis based on your health data."
    }

    // Generating shows a spinner as structured body content (no meta divider).
    private var bodyOverflow: AnyView? {
        guard isGenerating else { return nil }
        return AnyView(
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().tint(Theme.brandTeal)
                Text("Analyzing your health data… this may take up to 2 minutes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        )
    }

    // Empty state: prominent Generate button in the meta slot.
    private var footerOverflow: AnyView? {
        guard analysis == nil, !isLoading, !isGenerating else { return nil }
        return AnyView(
            Button(action: onGenerate) {
                Label("Generate Analysis", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandTeal)
        )
    }
}

// MARK: - Device sync card (Apple Health / Apple Watch)

private struct DeviceSyncCardView: View {
    let isConnected: Bool
    let heartRate: Int?
    let heartRateAt: Date?
    let lastSyncTS: Double
    let onTap: () -> Void

    private var subtitle: String {
        guard lastSyncTS > 0 else { return "Sync heart rate, steps & more" }
        return "Synced \(Date(timeIntervalSince1970: lastSyncTS).formatted(.relative(presentation: .named)))"
    }

    /// Compact age: 1s / 1m / 1h / 1d / 1y — whole numbers, no decimals.
    private func shortAge(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        switch s {
        case ..<60:        return "just now"
        case ..<3600:      return "\(s / 60)m ago"
        case ..<86400:     return "\(s / 3600)h ago"
        case ..<31_536_000: return "\(s / 86400)d ago"
        default:           return "\(s / 31_536_000)y ago"
        }
    }

    var body: some View {
        // Canonical card — §2A. Icon tile, teal title, connection status chip and subtitle come
        // from StandardCard slots; the inline heart-rate metric is bespoke footer content.
        StandardCard(
            icon: "applewatch",
            title: "Apple Health",
            titleColor: Theme.brandTeal,
            subtitle: subtitle,
            subtitleLineLimit: 1,
            // Status signal — §12: green = connected, orange = not connected.
            statusText: isConnected ? "Connected" : "Not connected",
            statusLevel: isConnected ? .green : .orange,
            footerView: metricView,
            date: (isConnected && heartRate != nil) ? heartRateAt.map(shortAge) : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // Once connected, the headline heart-rate metric fills the meta slot (bottom-left);
    // its age lands in the date slot (bottom-right) — same as every other card.
    private var metricView: AnyView? {
        guard isConnected, let hr = heartRate else { return nil }
        return AnyView(
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.brandTeal)
                Text("\(hr)").font(.title3.bold())
                Text("bpm").font(.caption).foregroundStyle(.secondary)
            }
        )
    }
}

// MARK: - Check-In card

private struct CheckInCardView: View {
    let checkIn: CheckInHomeCardResponse?
    let onTap: () -> Void

    var body: some View {
        StandardCard(
            icon: checkIn?.state == .allCaughtUp ? "checkmark.circle.fill" : "checkmark.circle",
            title: "Daily Check-In",
            titleColor: Theme.brandTeal,
            subtitle: checkIn?.subtitleText ?? "Loading…",
            statusText: checkIn?.stateLabel,
            statusLevel: checkIn?.stateLevel,
            ctaTitle: (checkIn?.canAccess != false) ? checkIn?.actionLabel : nil,
            ctaAction: onTap,
            date: checkIn.flatMap { relativeTime($0.lastCompletedAt) }
        )
        .contentShape(Rectangle())
        .onTapGesture { if checkIn != nil { onTap() } }
    }
}

// MARK: - Daily Advisory card

private struct DigestCardView: View {
    let digest: DailyDigestResponse?
    let isLoading: Bool
    @State private var isExpanded = false

    var body: some View {
        StandardCard(
            icon: "brain.head.profile",
            title: "Daily Advisory",
            titleColor: Theme.brandTeal,
            statusText: aqiChipText,
            statusLevel: aqiChipLevel,
            bodyText: bodyLine,
            bodyLineLimit: isExpanded ? nil : 3,
            // "Read more" is a CTA → canonical CTA slot/style.
            ctaTitle: (digest?.content.isEmpty == false) ? (isExpanded ? "Show less" : "Read more") : nil,
            ctaAction: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
        )
    }

    // AQI context chip when the digest includes air-quality info.
    private var aqiChipText: String? {
        guard let d = digest, d.showAqi == true, let v = d.aqiValue else { return nil }
        return "AQI \(v)"
    }
    private var aqiChipLevel: StatusLevel? {
        guard let d = digest, d.showAqi == true, let v = d.aqiValue else { return nil }
        return v < 51 ? .green : v < 101 ? .yellow : v < 201 ? .orange : .red
    }
    private var bodyLine: String? {
        if isLoading && digest == nil { return "Personalizing your advisory…" }
        if let c = digest?.content, !c.isEmpty { return c }
        return "Complete your health profile to receive a personalized daily advisory."
    }
}

// MARK: - AQI card

private struct AQICardView: View {
    let aqiData: AQIData?
    let aqiHistory: [AQIData]
    let city: String?
    let status: AQILoadStatus

    var body: some View {
        StandardCard(
            icon: "wind",
            title: "Air Quality",
            titleColor: Theme.brandTeal,
            statusText: chipText,
            statusLevel: chipLevel,
            bodyView: AnyView(
                // Min-height prevents the card jumping between states (requesting/loaded/denied).
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    stateContent
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            )
        )
    }

    // Health label chip moves to the canonical top-right slot (loaded only).
    private var chipText: String? {
        if case .loaded = status, let a = aqiData { return a.healthLabel }
        return nil
    }
    private var chipLevel: StatusLevel? {
        if case .loaded = status, let a = aqiData { return a.statusLevel }
        return nil
    }

    @ViewBuilder private var stateContent: some View {
        switch status {
        case .idle:
            EmptyView()

        case .requesting:
            HStack {
                ProgressView()
                    .tint(Theme.brandTeal)
                Text("Detecting location…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .loaded:
            if let aqi = aqiData {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(aqi.aqius)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(aqi.statusLevel.color)
                        Text(city ?? aqi.city)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pollutant = aqi.mainus {
                            Text("Main: \(pollutant.uppercased())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let temp = aqi.temperature {
                        Text("\(Int(temp))°C")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Mini trend chart if we have history
                if aqiHistory.count >= 2 {
                    let points = aqiHistory.reversed().enumerated().map { (i, a) in (i, a.aqius) }
                    Chart {
                        ForEach(points, id: \.0) { idx, val in
                            LineMark(x: .value("Day", idx),
                                     y: .value("AQI", val))
                            .foregroundStyle(Theme.brandTeal)
                        }
                    }
                    .frame(height: 48)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                }
            }

        case .denied:
            Label("Enable location to see local air quality", systemImage: "location.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .noData:
            Text("No AQI data available for your area yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dietary Insights card

private struct DietaryInsightsCardView: View {
    let insights: DietaryInsightsResponse?
    let isLoading: Bool
    var body: some View {
        StandardCard(
            icon: "leaf",
            title: "Dietary Insights",
            titleColor: Theme.brandTeal,
            bodyView: AnyView(dietaryBody)
        )
    }

    @ViewBuilder private var dietaryBody: some View {
        if isLoading && insights == nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Analyzing your diet…")
                Text("Recommendation list here…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .skeleton(isActive: true)
        } else if let di = insights {
            if di.foodsToEat.isEmpty && di.foodsToAvoid.isEmpty {
                Text("Add health data for personalized dietary guidance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !di.foodsToEat.isEmpty {
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(StatusLevel.green.color)
                        Text("Eat more: \(di.foodsToEat.prefix(3).joined(separator: ", "))")
                            .font(.subheadline)
                    }
                }
                if !di.foodsToAvoid.isEmpty {
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(StatusLevel.orange.color)
                        Text("Limit: \(di.foodsToAvoid.prefix(3).joined(separator: ", "))")
                            .font(.subheadline)
                    }
                }
            }
        } else {
            Text("Add health data for personalized dietary guidance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - NutriCheck card
// NutriCheck is its own feature (Android parity) — a dedicated launcher card, not a control
// on Dietary Insights. Tapping opens the NutriCheck sheet.
private struct NutriCheckCardView: View {
    let onTap: () -> Void

    var body: some View {
        StandardCard(
            icon: "fork.knife",
            title: "NutriCheck",
            titleColor: Theme.brandTeal,
            subtitle: "Check if a food fits your health profile",
            ctaTitle: "Check a food",
            ctaAction: onTap
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Feed preview section

private struct FeedPreviewSectionView: View {
    let items: [FeedItem]
    let isLoading: Bool
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label("Health Feed", systemImage: "newspaper")
                    .font(.headline)
                if isLoading { InlineLoader() }
                Spacer()
                Button("See All", action: onSeeAll)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brandTeal)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            if isLoading && items.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    FeedPreviewRowView(item: .placeholder)
                        .skeleton(isActive: true)
                }
            } else if items.isEmpty {
                GlassCard {
                    ContentUnavailableView("No Articles Yet", systemImage: "newspaper")
                }
            } else {
                ForEach(items) { item in
                    FeedPreviewRowView(item: item)
                }
                Button(action: onSeeAll) {
                    Text("See all articles →")
                        .font(.subheadline)
                        .foregroundStyle(Theme.brandTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
    }
}

private struct FeedPreviewRowView: View {
    let item: FeedItem

    var body: some View {
        StandardCard(
            leadingView: AnyView(
                AsyncImage(url: URL(string: item.imageUrl)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().foregroundStyle(.fill)
                }
                .frame(width: 48, height: 48) // feed preview thumbnail — leading-slot size
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.icon))
            ),
            title: item.title,
            titleFont: .subheadline.weight(.medium),
            titleLineLimit: 2,
            subtitle: (item.reason?.isEmpty == false) ? item.reason : nil,
            subtitleLineLimit: 1,
            statusText: item.isProOnly ? "Pro" : nil
        )
    }
}

// FeedItem.placeholder is defined in ServicesModels.swift

// MARK: - Workouts card

private struct WorkoutsCardView: View {
    let workouts: [WorkoutRecord]
    let isLoading: Bool
    let onSeeAll: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Label("Workouts", systemImage: "figure.run")
                        .font(.headline)
                        .foregroundStyle(Theme.brandTeal)
                    if isLoading { InlineLoader() }
                    Spacer()
                    Button("Manage", action: onSeeAll)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.brandTeal)
                }

                if isLoading && workouts.isEmpty {
                    Text("Loading workouts…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .skeleton(isActive: true)
                } else if workouts.isEmpty {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "figure.run").foregroundStyle(.secondary)
                        Text("Log your first workout to track your fitness.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                } else {
                    ForEach(workouts.prefix(3)) { workout in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.subheadline.weight(.medium))
                                Text("\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(workout.date.shortDate)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if workouts.count > 3 {
                        Text("+\(workouts.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Doctor section

private struct DoctorSectionView: View {
    let connected: [DoctorSearchResult]
    let incoming: [IncomingDoctorRequest]
    let isLoading: Bool
    let onManage: () -> Void
    let onRespond: (String, Bool) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Label("My Doctor", systemImage: "stethoscope")
                        .font(.headline)
                        .foregroundStyle(Theme.brandTeal)
                    if isLoading { InlineLoader() }
                    Spacer()
                    Button(connected.isEmpty ? "Find Doctor" : "Manage", action: onManage)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.brandTeal)
                }

                if isLoading && connected.isEmpty && incoming.isEmpty {
                    Text("Loading connections…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .skeleton(isActive: true)
                } else {
                    // Incoming requests — actionable inline
                    if !incoming.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Pending Requests")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(incoming) { req in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(req.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(req.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Button("Accept") { onRespond(req.email, true) }
                                            .buttonStyle(.borderedProminent)
                                            .tint(Theme.brandTeal)
                                            .font(.caption)
                                        Button("Decline") { onRespond(req.email, false) }
                                            .buttonStyle(.bordered)
                                            .tint(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                            Divider()
                        }
                    }

                    // Connected doctors
                    if connected.isEmpty {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No connected doctors")
                                    .font(.subheadline)
                                Text("Search for a doctor to connect your care.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    } else {
                        ForEach(connected.prefix(2)) { doc in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(doc.specialty)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusPill(text: "Connected", level: .green)
                            }
                        }
                        if connected.count > 2 {
                            Text("+\(connected.count - 2) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Inline loader
// Small branded spinner shown after a card's heading while that card's data is still loading.
// Used instead of the full-screen loader for the slow Services dashboard reads.
private struct InlineLoader: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(Theme.brandTeal)
    }
}

// MARK: - Time helper

/// Converts an ISO 8601 date string to a relative label — mirrors Android HomeFragment "X ago" labels.
private func relativeTime(_ isoString: String?) -> String? {
    guard let str = isoString else { return nil }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
        df.dateFormat = fmt
        if let date = df.date(from: str) {
            let diff = Date.now.timeIntervalSince(date)
            if diff < 60      { return "just now" }
            if diff < 3600    { return "\(Int(diff / 60))m ago" }
            if diff < 86400   { return "\(Int(diff / 3600))h ago" }
            return "\(Int(diff / 86400))d ago"
        }
    }
    return nil
}

// MARK: - Preview

#Preview { ServicesHomeView() }
