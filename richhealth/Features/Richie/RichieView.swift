import SwiftUI
import UIKit   // UIPasteboard — long-press "Copy" on chat bubbles

struct RichieView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm = RichieViewModel()
    @State private var logoSpinning = false
    @State private var expandedSuggestionID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                if vm.messages.isEmpty && !vm.isSending && !vm.isLoadingHistory {
                    emptyChatView
                } else {
                    messageListView
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // `.bar` backing so chat content can't read through the translucent input pill,
                // and the inset reserves the bar's height so the last message sits ABOVE it (not under).
                ChatInputBar(vm: vm)
                    .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Session title only — the spinning logo now lives above the greeting (empty state).
                ToolbarItem(placement: .principal) {
                    if let title = vm.currentSession?.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                // Matches Android fragment_ai top bar: chat-history on the LEFT, new-chat on the RIGHT.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await vm.loadSessions() }
                        vm.showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.startNewChat() } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: Binding(get: { vm.showHistory },    set: { vm.showHistory = $0 }))    { ChatHistorySheet(vm: vm) }
            .sheet(isPresented: Binding(get: { vm.showModelPicker }, set: { vm.showModelPicker = $0 })) { ModelPickerSheet(vm: vm) }
            .sheet(isPresented: Binding(get: { vm.showPaywall },     set: { vm.showPaywall = $0 }))    { PaywallView() }
            .sheet(isPresented: Binding(get: { vm.showDependentPicker }, set: { vm.showDependentPicker = $0 })) {
                DependentPickerSheet(vm: vm)
            }
            .sheet(isPresented: Binding(get: { vm.showComposer }, set: { vm.showComposer = $0 })) {
                ComposerDrawerSheet(vm: vm)
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Empty state

    private var emptyChatView: some View {
        ScrollView {
            // Group all Liquid Glass in the empty state into ONE container (Apple perf guidance:
            // effects outside a container degrade performance). spacing:0 keeps cards from merging.
            GlassEffectContainer(spacing: 0) {
            VStack(spacing: Theme.Spacing.l) {

                // Header — matches Android empty_state_container: 24dp horizontal padding,
                // welcome_logo 44×44, greeting + subtitle stacked below.
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // Continuously rotating logo — signals the AI is "alive" (moved here from the toolbar).
                    // .animation(_:value:) scopes the spin to this view so it can't leak into sibling
                    // layout (e.g. the input bar) the way a withAnimation-in-onAppear transaction would.
                    Image("AppLogo")
                        .resizable().scaledToFit()
                        .frame(width: Theme.IconSize.avatar, height: Theme.IconSize.avatar)
                        .rotationEffect(.degrees(logoSpinning ? 360 : 0))
                        .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: logoSpinning)
                        .onAppear { logoSpinning = true }
                    Text(timeGreeting(name: appEnv.auth.currentUser?.name))
                        .font(.title.bold()) // Android welcomeGreeting = 25sp bold
                    // Android subtitle — static instruction copy (fragment_ai.xml).
                    Text("Ask about your reports, symptoms or medications. I answer using what I know about you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.xxl)

                // Suggestion cards — accordion: collapsed by default, tap to expand.
                // Mirrors Android AIFragment "Suggested for you" section.
                if !vm.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        // "Suggested for you" label — mirrors Android sparkle prefix label
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Suggested for you")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.xs)

                        ForEach(vm.suggestions) { s in
                            let isExpanded = expandedSuggestionID == s.id
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                // Header row: sparkle icon + question + chevron
                                HStack(spacing: Theme.Spacing.s) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.brandTeal)
                                    Text(s.q)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                // Expanded: divider · "WHY RICHIE SUGGESTED THIS" · reason · Ask / Not helpful
                                if isExpanded {
                                    // Divider sits directly under the question row (matches Android expand divider).
                                    Divider()
                                    // "WHY RICHIE SUGGESTED THIS" — mirrors Android expanded suggestion header
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 9, weight: .semibold))
                                        Text("WHY RICHIE SUGGESTED THIS")
                                            .font(.system(size: 10, weight: .semibold))
                                            .tracking(0.4)
                                    }
                                    .foregroundStyle(Theme.brandTeal)

                                    // Android falls back to this copy when no reason is provided.
                                    Text(s.why.isEmpty ? "Tailored to your profile and health data." : s.why)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    HStack(spacing: Theme.Spacing.l) {
                                        Button {
                                            vm.input = s.q
                                            Task { await vm.send() }
                                        } label: {
                                            Text("Ask")
                                                .font(.callout.weight(.semibold))
                                                .padding(.horizontal, Theme.Spacing.s)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Theme.brandTeal)
                                        .controlSize(.regular)

                                        Button("Not helpful") {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                vm.dismissSuggestion(id: s.id)
                                            }
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .buttonStyle(.plain)

                                        Spacer()
                                    }
                                    .padding(.top, Theme.Spacing.xs)
                                }
                            }
                            .padding(Theme.Spacing.m)
                            // Expanded card gets a teal tint — mirrors Android #274545 stroke on expansion
                            .glassEffect(
                                isExpanded ? .regular.tint(Theme.brandTeal.opacity(0.08)) : .regular,
                                in: .rect(cornerRadius: Theme.CornerRadius.card)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedSuggestionID = isExpanded ? nil : s.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                }

                // Nudge card — placed below the suggestions. Icon chosen by nudge.type (mirrors Android hint_box:
                // leading icon · text · trailing forward arrow).
                if let nudge = vm.nudge, !nudge.text.isEmpty {
                    GlassCard {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: nudgeIcon(for: nudge.type))
                                .foregroundStyle(Theme.brandTeal)
                            Text(nudge.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                }
            }
            .padding(.bottom, Theme.Spacing.l)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Message list

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.m) {   // more margin between messages (was .s — too cluttered)
                    ForEach(vm.messages) { msg in
                        ChatBubbleView(
                            message: msg,
                            fontSize: vm.chatFontSize,
                            cards: vm.cardVMs[msg.id] ?? [],
                            onToggleSaved: { await vm.toggleSaved(message: msg) },
                            onAddCard: { card in await vm.addCard(card) },
                            onExtractLogs: { await vm.extractLogsFromConversation() }
                        )
                        .id(msg.id)
                    }

                    if vm.isSending {
                        ThinkingIndicatorView().id("typing")
                    }

                    // Session-level limit: chat is full, start new
                    if vm.limitKind == .sessionMessageLimit {
                        sessionLimitBanner.id("limitBanner")
                    }

                    // Monthly limit: cannot start new chat, must upgrade or wait for reset
                    if vm.limitKind == .monthlySessionLimit {
                        monthlyLimitBanner.id("limitBanner")
                    }

                    Color.clear.frame(height: Theme.Spacing.s).id("bottom")
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.m)   // clearance so the last bubble clears the input bar
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: vm.isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("typing") } }
            }
        }
    }

    // Session limit: this chat is full — user can start a new one
    private var sessionLimitBanner: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.s) {
                Label("This chat has reached its message limit.", systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.s) {
                    Button("Start New Chat") { vm.startNewChat() }
                        .buttonStyle(.borderedProminent).tint(Theme.brandTeal)
                    Button("Upgrade") { vm.showPaywall = true }
                        .buttonStyle(.bordered).tint(Theme.brandTeal)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // Monthly session limit: quota exhausted — cannot create new sessions this month
    private var monthlyLimitBanner: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Monthly chat limit reached", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline.weight(.medium))
                Text("You've used all your chat sessions for this month. Upgrade to continue, or wait until the 1st.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.s) {
                    Spacer()
                    Button("Upgrade to Pro") { vm.showPaywall = true }
                        .buttonStyle(.borderedProminent).tint(Theme.brandTeal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Input bar

    // Single floating glass card — mirrors Android's MaterialCardView input container.
    // TextField on top, action row (model pill · usage ring · Aa · send) below.
    // Its OWN View: typing (vm.input) now re-renders ONLY the bar — not the whole screen
    // (empty-state suggestion cards w/ glassEffect, spinning logo, message list). Fixes sluggish typing.
    struct ChatInputBar: View {
        @Bindable var vm: RichieViewModel
        @FocusState private var isInputFocused: Bool
        @State private var glowPulse = false
        @State private var showUsageInfo = false

        var body: some View {
        let blocked = vm.limitKind != nil
        return GlassEffectContainer(spacing: 0) {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Text input
            TextField("Message Richie", text: $vm.input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.vertical, Theme.Spacing.xs) // taller input box
                .disabled(blocked)
                .focused($isInputFocused)

            // Action row: model pill · dependent pill (left) · usage ring · Aa · send (right)
            HStack(spacing: Theme.Spacing.s) {
                // Model selector pill
                Button { vm.showModelPicker = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                        Text(vm.selectedModelDisplayName).font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .foregroundStyle(Theme.brandTeal)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.brandTeal.opacity(0.12), in: Capsule())
                }
                .disabled(blocked)

                // Family member selector — mirrors Android inputProfileChip.
                // Locked after first message (dependentId is set at session creation).
                if !vm.dependents.isEmpty {
                    let locked = vm.currentSession != nil || blocked
                    Button { vm.showDependentPicker = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: locked ? "lock.fill" : "person.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(vm.selectedDependent?.name ?? "Me")
                                .font(.system(size: 11, weight: .bold))
                            if !locked {
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                }

                Spacer()

                // Usage ring — tap for "X of Y used · Z remaining" — mirrors Android usage toast
                if let used = vm.messagesUsed, let limit = vm.messageLimit, limit > 0 {
                    let fraction = Double(used) / Double(limit)
                    Button { showUsageInfo = true } label: {
                        UsageRing(value: min(fraction, 1.0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showUsageInfo) {
                        Text("\(used) of \(limit) messages used · \(max(0, limit - used)) left this session")
                            .font(.caption)
                            .padding(Theme.Spacing.m)
                            .presentationCompactAdaptation(.popover)
                    }
                }

                // Expand — opens the composer drawer for a large, full-view typing area
                Button { vm.showComposer = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(blocked)

                // Aa font size cycle — mirrors Android text_size_button
                Button { vm.cycleChatFontSize() } label: {
                    Text(vm.chatFontSizeLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Send button
                Button { Task { await vm.send() } } label: {
                    Image(systemName: vm.isSending ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            vm.input.trimmingCharacters(in: .whitespaces).isEmpty || blocked
                                ? Color.secondary : Theme.brandTeal
                        )
                }
                .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending || blocked)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        // The bar floats over the scroll content (keyboard raises it above the suggestions).
        // Make the whole bar an opaque hit target so taps NEVER fall through to the cards behind —
        // otherwise the expand/Aa/send buttons "animate" but the card underneath receives the tap.
        .contentShape(Rectangle())
        // "Boundy" — teal glow border: soft when focused, pulsing when AI is generating
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    vm.isSending
                        ? Theme.brandTeal.opacity(glowPulse ? 0.85 : 0.3)
                        : (isInputFocused ? Theme.brandTeal.opacity(0.5) : Color.clear),
                    lineWidth: vm.isSending ? 2 : 1
                )
                .shadow(
                    color: vm.isSending ? Theme.brandTeal.opacity(glowPulse ? 0.35 : 0) : .clear,
                    radius: 6
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: isInputFocused)
        }
        .task(id: vm.isSending) {
            guard vm.isSending else { glowPulse = false; return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.8)) { glowPulse = true }
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation(.easeInOut(duration: 0.8)) { glowPulse = false }
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        }
        }
    }

    // MARK: - Helpers

    /// Time-aware greeting matching Android showWelcomeMessage() logic.
    private func timeGreeting(name: String?) -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let prefix: String
        switch hour {
        case 5..<12:  prefix = "Good morning"
        case 12..<17: prefix = "Good afternoon"
        case 17..<21: prefix = "Good evening"
        default:      prefix = "Hey"
        }
        if let firstName = name?.split(separator: " ").first.map(String.init), !firstName.isEmpty {
            return "\(prefix), \(firstName)"
        }
        return prefix
    }

    /// Map nudge.type → SF symbol — mirrors Android type-to-icon switch in AIFragment.
    private func nudgeIcon(for type: String) -> String {
        switch type {
        case "add_measurements": return "waveform.path.ecg"
        case "add_symptoms":     return "info.circle"
        case "add_family":       return "person.2.fill"
        case "freshness":        return "clock.arrow.circlepath"
        case "add_reports":      return "doc.text.fill"
        case "add_meds":         return "pills.fill"
        default:                 return "lightbulb"
        }
    }
}

// MARK: - Chat bubble

private struct ChatBubbleView: View {
    let message: ChatMessage
    let fontSize: CGFloat
    let cards: [HealthCardVM]
    let onToggleSaved: () async -> Void
    let onAddCard: (HealthCardVM) async -> Void
    let onExtractLogs: () async -> Void
    @State private var showReasoning = false

    var body: some View {
        switch message.kind {
        case .user: userBubble
        case .ai:   aiBubble
        case .log:  logEntry
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text)
                .font(.system(size: fontSize))
                .padding(.horizontal, Theme.Spacing.m).padding(.vertical, Theme.Spacing.s)
                .background(Theme.brandTeal, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.card))
                .foregroundStyle(.white) // white text on teal for contrast
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = message.text
                    }
                }
        }
    }

    private var aiBubble: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Thinking trace — ABOVE the message (matches Android item_chat_ai.xml order), collapsed by default.
                // Custom expander: LEADING chevron that rotates 0°→90° on expand (no trailing chevron/brain icon).
                if let reasoning = message.reasoning {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Button {
                            withAnimation(.easeInOut) { showReasoning.toggle() }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "brain")
                                Text("Thought process")
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(showReasoning ? 90 : 0))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, Theme.Spacing.xs)   // breathing room around the row
                        }
                        .buttonStyle(.plain)

                        if showReasoning {
                            Text(reasoning)
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, Theme.Spacing.xs)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                }

                ChatMarkdownText(text: message.text, fontSize: fontSize)
                    .padding(.horizontal, Theme.Spacing.m).padding(.vertical, Theme.Spacing.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.card))
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = message.text
                        }
                        Button(message.isSaved ? "Unsave" : "Save",
                               systemImage: message.isSaved ? "bookmark.slash" : "bookmark") {
                            Task { await onToggleSaved() }
                        }
                        Button("Log & remember from here", systemImage: "text.badge.plus") {
                            Task { await onExtractLogs() }
                        }
                    }

                // Quick-log cards attached to this AI reply (Android dataCards).
                ForEach(cards) { card in
                    HealthCardView(card: card, onAdd: { await onAddCard(card) })
                }

                if message.memorySaved {
                    Label("Remembered", systemImage: "brain.head.profile")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, Theme.Spacing.m)
                }
            }
            Spacer(minLength: 60)
        }
    }

    private var logEntry: some View {
        Text(message.text)
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = message.text
                }
            }
    }
}

// MARK: - Thinking indicator

/// Rotates through phases to match Android AIFragment escalating thinking text.
private struct ThinkingIndicatorView: View {
    private let phases = [
        "Thinking…",
        "Still thinking…",
        "Working through your data…",
        "Almost there…",
        "Just a moment more…"
    ]
    @State private var phaseIndex = 0
    // Drives the spinning logo (same pattern as the empty-state logo) — signals the AI is working.
    @State private var logoSpinning = false

    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.s) {
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: Theme.IconSize.inline, height: Theme.IconSize.inline)
                    .rotationEffect(.degrees(logoSpinning ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: logoSpinning)
                    .onAppear { logoSpinning = true }
                Text(phases[phaseIndex])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.3), value: phaseIndex)
            }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.CornerRadius.card))
            Spacer(minLength: 60)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard phaseIndex < phases.count - 1 else { break }
                withAnimation(.easeInOut(duration: 0.3)) {
                    phaseIndex += 1
                }
            }
        }
    }
}

// MARK: - Chat history sheet

private struct ChatHistorySheet: View {
    var vm: RichieViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var filteredSessions: [ChatSessionDTO] {
        guard !searchQuery.isEmpty else { return vm.sessions }
        return vm.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            ($0.lastMessage?.localizedCaseInsensitiveContains(searchQuery) == true)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingHistory {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Previous Chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your past conversations will appear here.")
                    )
                } else {
                    List {
                        ForEach(filteredSessions) { session in
                            Button {
                                Task { await vm.openSession(session) }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack {
                                        Text(session.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        Spacer()
                                        if let ago = timeAgo(session.timestamp) {
                                            Text(ago)
                                                .font(.caption2)
                                                .foregroundStyle(Theme.brandTeal)
                                        }
                                        if session.isLimitReached == true {
                                            StatusPill(text: "Full", level: .yellow)
                                        }
                                    }
                                    if let last = session.lastMessage, !last.isEmpty {
                                        Text(last)
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let count = session.messageCount, count > 0 {
                                        Text("\(count) messages")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                if let session = filteredSessions[safe: index] {
                                    Task { await vm.deleteSession(session) }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchQuery, prompt: "Search conversations")
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Relative time string — mirrors Android session_time TextView ("3h ago").
    private func timeAgo(_ isoString: String?) -> String? {
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
}

// MARK: - Model picker sheet

private struct ModelPickerSheet: View {
    var vm: RichieViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RichieViewModel.allModels, id: \.id) { model in
                        Button {
                            if model.isPro {
                                dismiss()
                                vm.showPaywall = true
                            } else {
                                vm.selectedModel = model.id
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(model.name)
                                    .font(.subheadline)
                                    .foregroundStyle(model.id == vm.selectedModel ? Theme.brandTeal : .primary)
                                Spacer()
                                if model.isPro { StatusPill(text: "PRO") }
                                if model.id == vm.selectedModel {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.brandTeal)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Pro models require an active Pro subscription.")
                }
            }
            .navigationTitle("Choose model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Dependent picker sheet

private struct DependentPickerSheet: View {
    var vm: RichieViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // "Me" — always the first option
                    Button {
                        vm.selectedDependent = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Me (default)")
                                .foregroundStyle(vm.selectedDependent == nil ? Theme.brandTeal : .primary)
                            Spacer()
                            if vm.selectedDependent == nil {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.brandTeal)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(vm.dependents) { dep in
                        Button {
                            vm.selectedDependent = dep
                            dismiss()
                        } label: {
                            HStack {
                                Text(dep.name)
                                    .foregroundStyle(vm.selectedDependent?.id == dep.id ? Theme.brandTeal : .primary)
                                Spacer()
                                if vm.selectedDependent?.id == dep.id {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.brandTeal)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Chat on behalf of a family member. The selection is locked after the first message in a session.")
                }
            }
            .navigationTitle("Chat for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Composer drawer

/// Full-view typing area for Richie — same implementation as Profile → Custom Instructions
/// (`CustomInstructionsEditorSheet`), just bound to `vm.input` so text flows both ways.
private struct ComposerDrawerSheet: View {
    var vm: RichieViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DarkRoundedTextEditor(
                text: Binding(get: { vm.input }, set: { vm.input = $0 }),
                placeholder: "Message Richie — type as much as you like…",
                minHeight: 200
            )
            .padding(Theme.Spacing.m)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview { RichieView().environment(AppEnvironment()) }
