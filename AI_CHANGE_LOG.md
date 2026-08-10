# AI Change Log — RichHealth iOS

---

## [2026-08-10] Richie chat polish + full signup parity + logging/memory (main branch)

Cross-platform pass (iOS + Android + backend). iOS work:

**Chat (Features/Richie)**
- **Copy**: long-press (context menu) now offers Copy on user, AI and log messages (`UIPasteboard`, raw text) — matches Android.
- **"Thought process"**: replaced the `DisclosureGroup` with a custom expander — a LEADING rotating chevron + "Thought process" label (was "Thinking" with a trailing chevron + brain icon). Aligned with Android.
- **Formatting**: new `DesignSystem/Components/ChatMarkdownText.swift` renders headings, bullet/numbered lists, bold/italic/strikethrough, and reflows markdown tables to key:value — mirrors Android's `TextFormatter` (iOS previously rendered inline-only markdown). Wired into AI messages.
- **Logo**: the app logo now also spins in the "thinking" indicator while a reply loads (empty-state spin kept).
- **Memory indicator**: `SendMessageResponse` decodes `memoriesAdded` (objects with `fact`) so the "Remembered" badge shows on fresh replies, not only after reload.
- **Extract-logs**: new `ChatService.extractLogs` + `RichieViewModel.extractLogsFromConversation()`, triggered by a "Log & remember from here" context-menu action, calling the new backend endpoint and appending a confirmation.

**Auth (Features/Auth)**
- **Login**: rotating logo; added email-format validation and distinct timeout/offline/401/server error messages (ported from Android).
- **Signup — full parity with Android onboarding**: new reusable `DesignSystem/Components/SelectableCardGrid.swift` (single/multi-select cards + "Other" free-text + mutually-exclusive "None"); added ~24 missing fields incl. the gender-conditional Menstrual section, conditional smoking/alcohol/condition-detail steps, family history, medication categories, ethnicity, and lifestyle fields; allergies/conditions converted from free-text to multi-select; dynamic conditional steps (was fixed 5). `SignupRequest`/`UserProfile` extended to match the Android payload keys.

**Backend (../richhealthbackend)** — root-cause dedup so the card extractor stops re-suggesting already-logged items; new `POST /api/chat/sessions/:id/extract-logs` (last 2 messages → create logs + memory, with dedup, reusing `storeMemory`/`markHealthDataUpdate`).

Verified by independent no-context audit agents (compile-risk + backend↔client contract); fixed a `memoriesAdded` decode mismatch before commit.

## [2026-08-09] Services cards — follow-up polish (owner review of the rendered build)

- **Removed the meta Divider** from `StandardCard` (Android has none) — cards are cleaner.
- **Date is a bare "X ago", kept bottom-right** (owner: it was the label that was inconsistent, not the position). Dropped the descriptive prefix; Android's "Last insight/Updated/Checked/Last check-in" prefixes were stripped to match.
- **Removed the "New data — tap to refresh insights" warning** from the Health Analysis card — the yellow attention chevron already conveys "out of date", so the banner was redundant.
- In-sheet cards that still use a CTA/footer keep CTA-left + date-right on one line. §27 updated.
Files: `DesignSystem/Components/StandardCard.swift`, `Features/Services/ServicesHomeView.swift`, `CLAUDE.md`.

---

## [2026-08-09] Services cards — status chevron + whole-card tap, no CTAs (cross-platform consistency pass)

Owner goal: make the Services dashboard cards fully consistent AND matched to Android — one component, no scattered CTAs, a status-colour chevron, and the heart-rate reading moved off the Apple Health card face. Done alongside matching Android work (new reusable `ServiceCardView`) and a small backend addition; iOS card SET unchanged (Workouts/Doctor stay exempt).

**`DesignSystem/Components/StandardCard.swift`**
- Added a trailing status `chevron:` slot (`enum Chevron { normal, attention, urgent }`) — vertically centred, thin (`chevron.right`, 15pt semibold). Colour is a status signal SEPARATE from the chip: `.urgent` red, `.attention` yellow, `.normal` tertiary.
- Added `onTap:` — the WHOLE card is now the tap target (card density only; rows keep their own gestures). Wrapped in a `.plain` Button for accessibility.
- Icon now pinned to the top edge on tall cards; content column `.topLeading`. `ctaTitle`/`ctaAction`/`footerView` kept for in-sheet cards only.

**`Features/Services/ServicesHomeView.swift`** — removed ALL dashboard CTAs; every card is now tap-to-open with a chevron:
- Health Analysis: chevron red if status critical → yellow if data changed → normal; tap opens analysis (or generates the first one). Removed the "Generate"/"View Full Analysis" buttons.
- Apple Health: **heart-rate metric removed from the card face** (it's inside `WatchSyncSheetView`); face = status chip + last-sync date; chevron normal; tap opens the sheet.
- Daily Check-In: chevron yellow when due/pending/in-progress; tap opens check-in.
- Daily Advisory: removed "Read more" — tap expands inline; chevron yellow when `stale`; date = `generatedAt`.
- Dietary Insights: date = `lastUpdated`; chevron yellow when `stale`; tap refreshes (new `refreshDietary()` on the VM).
- NutriCheck launcher: shows "Last checked" date + yellow chevron when new health data since last check (`lastNutriCheckAt` vs `lastHealthDataChange`).
- AQI left as an informational card (no chevron/tap — no destination); Workouts & Doctor remain owner-exempt.

**`Models/ServicesModels.swift`** — `DailyDigestResponse` +`generatedAt`/`stale`; `DietaryInsightsResponse` +`lastUpdated`/`stale`; `HealthAnalysis` +`lastNutriCheckAt`/`lastHealthDataChange` (all already in the backend response; the last two are exposed by the analysis endpoint).

**Backend (../richhealthbackend)** — `daily-digest` now returns `generatedAt`+`stale`; `dietary-insights` now returns `lastUpdated`+`stale`. Additive, non-breaking.

§27 updated to document the chevron/tap contract.

---

## [2026-08-09] StandardCard — one canonical card+row layout (fixed slot map)

Audited every card/list across all 17 owner screenshots + the live code (3 Explore agents: HealthHub sheets, Services cards, Profile/Richie). Built ONE canonical layout with a **fixed slot map** — every value has one reserved position and never moves based on what else is present. A card with {title, subtitle, chip} and a card with {…, date} put each shared value in the identical place; a 5th/bespoke value goes to a footer overflow slot, never into a reserved slot.

Slots (fixed): icon(leading) · category(teal caps, above title) · title · subtitle(short, always directly under title) · status chip(top-right) · date(right, directly under chip) · body(long text, full-width below) · warning(orange banner) · footer(overflow). Crucially `subtitle` and `body` are DISTINCT slots — no "hug-title-vs-full-width" conditional; layout is deterministic.

Density unifies lists and cards with the SAME slot map:
- `.card` → wrapped in GlassCard (Services/detail cards).
- `.row`  → no wrapper, list-row padding (Health Hub lists).

Slots (fixed): icon/leadingView(leading) · category(teal caps) · title · subtitle(short, under title) · status chip(top-right) · body(long text) · warning(orange) · date(**bottom-left**, owner decision) · footer(overflow, bottom-right). Actions (Manage/NutriCheck/Generate/thumbs) live in the footer — top-right is chip-only. `subtitle`/`body` font unified (no per-card `.caption` overrides) so text size/location/margin are identical everywhere.

Files:
- `DesignSystem/Components/StandardCard.swift` (new) — component + convenience init. Deterministic slot layout; `leadingView: AnyView?` for image/avatar leading (same 48/44 frame as the icon tile); `titleLineLimit`.
- `DesignSystem/Components/HealthRecordRow.swift` (rewritten) — thin wrapper over `StandardCard(density: .row)`. Public API unchanged → all 5 Health Hub lists route through the canonical layout, no call-site changes. **Proof lists and cards share one structure.**
- `Features/Services/ServicesHomeView.swift` — migrated dashboard cards to StandardCard: Briefing, Health Analysis, Apple Health (DeviceSync), Daily Check-In, Daily Advisory (Digest), Air Quality (AQI), Dietary Insights, Feed preview row. **Left as-is per owner:** Workouts and My Doctor sections (reverted after an initial migration).
- `Features/Services/NutriCheckSheetView.swift` — `NutriCheckHistoryRow` migrated (title + chip + body reason + stale warning + date; thumbs = footer).
- Build verified green throughout. Not migrated: Feed section header, StatChip/WatchStatChip/HubCard (Health Hub tab), and in-sheet cards (Health Analysis sheet, Check-In sheet, Doctor/Workout sheets) — next pass if desired.

### Follow-up (same day) — fixed 7 owner-reported consistency defects from the rendered screenshot
Rewrote `StandardCard` so the icon sits left and EVERYTHING else lives in one content column (fixes body/subtitle misalignment — long text no longer starts at the card edge). Component now draws a consistent `Divider` before a meta row; **date is bottom-right, CTA/footer bottom-left** on every card; a single `ctaTitle`/`ctaAction` gives all text CTAs one style/position (View Full Analysis, Check-In action, Read more); added `bodyView` (structured full-width body: AQI number+chart, Dietary eat/limit, Briefing bullets) and `footerView` (metric/progress); removed leftover `.caption` subtitle/body overrides so text size is uniform. `HealthRecordRow` unchanged API (rows keep chip-over-date on the right).
- NutriCheck taken OFF the Dietary Insights card (Android: it's a separate feature) → new dedicated `NutriCheckCardView` launcher; `onNutriCheck` removed from Dietary; NutriCheck sheet still reachable.
- §27 added to CLAUDE.md documenting the locked StandardCard contract.
- **Verified by two independent no-context audit agents** — all requirements PASS (only residual: intentional smaller title on Briefing/Feed item cards).

### Follow-up 2 (same day) — NutriCheck result card + consistent card padding
- `NutriCheckResultCard` was the last hand-rolled NutriCheck card (own `Divider` + "Based on:" label, no date) → migrated to `StandardCard`: same layout as the history rows, "Based on:" is now the footer, and the freshly-computed result shows a "Just now" date (the model has no timestamp field). Title size matched to the history rows (`.subheadline.semibold`). Fixes the "NutriCheck missing date / some have labels, others don't" inconsistency.
- Consistent card spacing (owner: "a tad, consistently"): new `Theme.Spacing.cardPadding = 20`. `GlassCard` inner padding `m`(16) → `cardPadding`(20) — a touch more breathing room inside EVERY card app-wide (one place to tune). Services card list gap `m`(16) → `cardPadding`(20) so the space between/around cards matches, uniform across all Services cards incl. the exempt Workouts/Doctor.
- Build green.

---

## [2026-08-09] Canonical sheet close button — teal (X) replaces every "Done"

Every bottom sheet's "Done" dismiss button is now a brand-teal `xmark` toolbar button — one canonical close affordance app-wide (§2A). No custom glass/effect: in iOS 26 a toolbar button is already a native glass button with native tap behavior, so the component only supplies the teal glyph (§C8 — don't fight the framework; an earlier `.glassEffect(.interactive())` version added an unwanted tap shimmer). Shared component applied to all 12 sheet Done buttons; also refactored Legal's inline copy to use it.

Files:
- `DesignSystem/Components/SheetCloseButton.swift` (new) — `SheetCloseButton { dismiss() }`.
- Replaced `Button("Done") { dismiss() }` (incl. `.bold()` variants) with `SheetCloseButton`:
  `WatchSyncSheetView`, `MedicalReportsSheetView` (×2), `CheckInSheetView`, `HealthAnalysisSheetView`,
  `ProfileView` (Usage, AI Memory, Custom Instructions), `RichieView` (history, model picker, dependent picker, composer).
- `LegalHubSheet` — inline teal-X toolbar item swapped for the shared component.
- Left untouched: `Cancel` buttons on form sheets (distinct discard semantic + Save), and CheckIn's in-flow `Next/Done` submit label (not a dismiss).

---

## [2026-08-09] Richie in-chat quick-log cards (Android dataCards) + editable time

Ported Android's in-chat health cards: the AI reply can attach 0–5 quick-log cards (symptom / measurement / medication / period) that the user edits inline and saves with one tap. **Added feature:** an editable time/date on every card (defaults to now, always sent — the save endpoints already accept a timestamp, so NO backend change). Cards are ephemeral (never persisted, don't reappear on session reload); the "logged" confirmation is persisted via `/log`. All saves reuse the existing HealthHub services — no new networking. Card saves use `showsLoader: false` (inline `ProgressView` on the Add button, not the global loader).

Pre-implementation research (§25/C2): 3 parallel agents (Android XML `item_chat_health_card.xml`/`item_chat_log.xml` + `ChatAdapter.HealthCardViewHolder`; Android Java `AIFragment`/`HealthLogParser`/`HealthCard`; current iOS Richie). Backend contract verified in `../richhealthbackend`: `dataCards` is top-level on the send response (`rhChatController.js` ~line 632, gated by `aiPreferences.autofillCards`), and `POST /api/chat/sessions/:id/log` takes `{text}` and returns a `type:"log"` message (`rhChatController.logDataEntry`, `chatRoutes.js:36`).

Files:
- `Models/ChatModels.swift` — added `HealthCardKind` enum + `HealthCardDTO` (decode defaults: severity/painLevel clamp 1–5, flowIntensity normalized light|medium|heavy, frequency non-empty→"As needed"); `dataCards: [HealthCardDTO]?` on `SendMessageResponse`; `cards: [HealthCardDTO]` on `ChatMessage`.
- `Features/Richie/ChatService.swift` — `logDataEntry(sessionId:text:)` → `POST /api/chat/sessions/:id/log`, `showsLoader:false`.
- `Features/Richie/HealthCardVM.swift` (new) — `@Observable @MainActor` interaction state per card (expanded / edited fields / editable `date` / status editable→added→dismissed). `validate()` (symptom: title+duration; measurement: title+value+unit; medication: name+dosage; period: none), `save()` (reuses HealthDataService/MedicationService/PeriodLogService with `shareWithFamily:false`, `includeInChat:true`, medication `isOngoing:true`, never `endDate`; date+time ISO8601 for symptom/measurement, date-only UTC for medication/period — same encoding as the sheets), `confirmationText()` (Android format). Frequency display-only.
- `Features/Richie/HealthCardView.swift` (new) — `GlassCard` per card; collapsed header (teal kind icon + label + chevron) → expanded native fields + `DatePicker` (Time for symptom/measurement, Date for medication/period) + Add (borderedProminent teal, inline spinner) / Dismiss. Terminal `.added`: collapsed, green check, "Added ·". Plain fields, no per-field backgrounds (C3).
- `Features/Richie/RichieViewModel.swift` — `cardVMs: [String:[HealthCardVM]]` keyed by AI message id (lives in the VM so state survives LazyVStack recycling → no double-log); populated in `send()`; cleared on `openSession`/`startNewChat`. `addCard()` saves → terminal + posts `/log` confirmation; 429/403 → paywall, else inline error.
- `Features/Richie/RichieView.swift` — pass `cards`/`onAddCard` into `ChatBubbleView`; render `HealthCardView`s under the AI text in `aiBubble`.

---

## [2026-08-08] First-tap keyboard hang RESOLVED (debug-tether artifact) + cleanup

Confirmed on device: launched from the home screen **fully untethered from Xcode**, the first-tap is instant. The 3s stall + `Reporter disconnected {function=sendMessage}` only happen while attached to the Xcode debugger (those are the debug os_log reporters). It's a dev-only artifact of the iOS 18/26 RTIInputSystem cold-start under the debugger — nothing to fix for shipping users. All the pre-warm / splash-inflation / `OS_ACTIVITY_MODE` hacks were removed (they didn't work; the log even proved a real warm doesn't cache).

Cleanup + related real changes:
- Removed all diagnostics: the DEBUG plain `TextField`, focus logs, and load timing logs.
- Removed the `OS_ACTIVITY_MODE=disable` env var from the shared scheme (bandaid, didn't suppress the log).
- **Richie launch slimmed:** dropped the empty-state health-summary subtitle, which block-fetched two slow `/stats` endpoints at launch (`/medical-data/stats` was 9s for 2KB) — redundant with HealthHub, one line of text not worth it.
- Kept the earlier `APIClient` off-main (`nonisolated`) decode — that's a genuine §1.5 improvement regardless.
- Chat empty state: more top breathing room for the logo/greeting (`Theme.Spacing.xxl` = 48; new token added).

## [2026-08-08] First-tap keyboard hang — ROOT CAUSE: JSON decode on MainActor

Deep search on the exact logs (`Result accumulator timeout: 3.0`, `Reporter disconnected {sendMessage}`, RTIInputSystem `sessionID`) → the iOS 18/26 first-tap stall occurs when the app saturates the main actor / XPC at launch so the keyboard's RTIInputSystem session can't negotiate (canonical trigger: Firebase = heavy startup work; mitigation: defer startup work). Apple 808229.

Our equivalent: `APIClient` is `MainActor`-default, so it decoded EVERY response ON THE MAIN THREAD. At launch we fire profile (~49KB), feed (~26KB), briefing, dietary, 2× /stats — all decoded on main → starves the keyboard's first-tap session → 3s gate timeout. Also violated CLAUDE.md §1.5 ("network hops off-main inside APIClient").

Fix: `APIClient.send`, `send<T>`, `sendMultipart` are now `nonisolated` → request + JSON decode run OFF the main actor; only a quick `MainActor.run` hop to toggle the loader. `String.data` helper marked `nonisolated` too. Diagnostics (DEBUG plain field + focus logs) still in place pending user test. Reverted earlier KeyboardWarmer + 3.0s splash (didn't help). Build ✅.

## [2026-08-08] First-tap keyboard hang v2 — hold the warm-up long enough

New logs (`Result accumulator timeout: 3.000000, exceeded`, `…update accumulator after completion has already been called`) + forum match (`UIEmojiSearchOperations`) pinpoint it: iOS RTIInputSystem's cold **emoji-search session** with a hard ~3s reporter gate. It's an OS-level bug (repro on stock apps, still in iOS 26.1); the `Reporter disconnected {sendMessage}` lines are the debugger amplifying it.

Why v1 (one-run-loop warm) failed: the session needs ~3s to establish; resigning next run-loop tore it down before it finished. Fix: `KeyboardWarmer.warm(holdFor:)` now HOLDS first responder ~2.5s (off-screen) so the session fully establishes once (cached process-wide → first real tap instant). Started ~200ms into launch; splash floor raised 2.5s→3.0s so the hold completes before the UI is interactive (no keyboard flash).

Caveat: mitigation for an Apple bug, not a code bug on our side — verify on a real device in a Release build NOT attached to Xcode (the debugger massively worsens it). Build ✅.

## [2026-08-08] Fix first-tap keyboard hang (KeyboardWarmer was a no-op)

Root cause of the first-tap freeze + "Gesture: System gesture gate timed out" / RTI / XPC "Reporter disconnected": the RemoteTextInput keyboard cold-start wasn't being pre-paid because `KeyboardWarmer` set `field.isHidden = true` — a hidden view **cannot** become first responder, so `becomeFirstResponder()` returned false and nothing warmed. It also resigned in the same run-loop tick.

Fix (`KeyboardWarmer.swift`): off-screen (1×1, negative origin) but NOT hidden field; `becomeFirstResponder()`; resign + remove on the NEXT run-loop so the RTI session actually initializes. Still invoked ~400ms into launch (behind the 2.5s splash) so the spin-up is off-screen. Build ✅.

Note: the `Reporter disconnected` XPC lines indicate the stall is largely a DEBUGGER-attached artifact (well-documented RTIInputSystem behavior) — verify standalone (run without Xcode attached).

## [2026-08-08] Profile: loader on load + on edit-save

- **Profile tab load** now shows the branded loader ("Loading your profile…"). `loadProfile`/`refreshProfile` gained a `showsLoader` param; `ProfileViewModel.load` passes `true` so the user-values fetch (the slow ~3.6s `GET /api/user/profile`) is covered. Login/signup/paywall refreshes stay silent (own spinner / behind sheet). proAccess/usage/relationships remain silent (fast, skeleton-backed).
- **Profile edit save** now shows a branded loader INSIDE EditProfileSheet (`.overlay` on `vm.isSaving`, "Saving your profile…"). The sheet stays up during save, so the global overlay would be occluded — the sheet-local one is what's visible. Build ✅.

## [2026-08-08] Silence OS keyboard log + remove Apple readings log

- Removed the `[RH] Apple Health readings (…)` debug dump (`logReadingsJSON()` + the `readingsJSON` helper that only fed it) from `HealthKitManager`.
- The `[MC] Reading from public effective user settings` console line is OS-generated (Managed Configuration, fires when the keyboard/text-input system initializes — our `KeyboardWarmer` triggers it at launch). Not an error, no perf impact (web-confirmed). Silenced it by adding a **shared scheme** (`xcshareddata/xcschemes/richhealth.xcscheme`) with launch env var `OS_ACTIVITY_MODE=disable`. Keeps `[RH]` print logs; hides OS unified-logging noise. Run-only; no code/behavior change. Build ✅.

## [2026-08-08] Apple dedup: reconcile with backend + delete older duplicates

The local UUID ledger only *prevented new* duplicates — it never removed the ones already on the server (pre-fix history + the one extra set created on the first post-fix sync when the ledger was empty), and it's lost on reinstall/logout. So the list still looked replicated.

`HealthKitManager.saveAll` now **reconciles against the backend** each sync (still no schema change):
1. `list(type:"measurement", limit:200)` → filter `isFromAppleWatch`, sort newest-first by `createdAt`.
2. Group by dedup key and **delete the older duplicate rows** (`service.delete`). Point metrics key on the exact second (distinct daily readings are kept); aggregates (Steps/Active Energy/Sleep) key **per calendar day** — historical aggregate rows were posted with a moving `now` timestamp, so per-second wouldn't catch them.
3. Skip re-posting any reading whose key already exists on the server; otherwise post.
Local `syncedKeys` ledger kept as a session fast-path. list/delete are `showsLoader:false` (no loader flash). Cleanup runs every (throttled) sync, so deep history converges over a few syncs (200/pass). Build ✅.

## [2026-08-08] Loader leak sweep + message fixes

Full audit of every `showsLoader:true` call → its call sites → context:
- **Signup flow** (`signup`, `sendOTP`, `verifyOTP`) → `showsLoader:false`. SignupView has its own inline spinners ("Verifying…" + button) — was a double loader.
- **`loadProfile`** → `showsLoader:false`. Called via `refreshProfile` from the Paywall sheet (post-purchase) and after profile edit → branded loader was rendering behind the sheet / as a stray overlay. Login/signup already show their own progress.
- **Profile tab reads** (`fetchProAccess`, `fetchUsage`, `relationships`) → `showsLoader:false`. ProfileView already shows skeletons; branded overlay was redundant AND the shown message was nondeterministic (4 concurrent calls → could read "Loading your family…" on tab entry).
- **Message fix:** both HealthHub `getStats` now say "Loading your health data…" (was "Loading your health summary…" / "Loading your medications…") so the landing reads correctly regardless of which concurrent call begins last.

Net: the branded full-screen loader now appears in exactly ONE place — the HealthHub tab landing (its original intended use). All sheets, auth, profile, chat, and dashboard reads are silent (own skeletons/inline/button spinners). Build ✅.

## [2026-08-08] Fix: branded loader was covering the chat screen for ~7s

Audit finding: `RichieViewModel.loadHealthSummary()` calls `HealthDataService.getStats()` + `MedicationService.getStats()` to build the empty-state subtitle. Those two were `showsLoader: true` (kept as the HealthHub-tab landing blocker), so Richie — reusing the same functions — got the full-screen branded loader over the chat until both `/stats` returned (up to ~7.4s; backend cold-start, staggered completions).

Fix: `getStats(showsLoader: Bool = true)` on both services. HealthHub keeps the blocker (default); `RichieViewModel` passes `showsLoader: false` so the chat empty state renders instantly and the subtitle fills in when ready. Build ✅.

## [2026-08-08] Splash warmup + no loader on splash/login

- **No loader on splash or login.** `AuthManager.bootstrap` profile GET → `showsLoader:false` (splash IS the launch screen). Login POST → `showsLoader:false` (the Log in button already shows an inline "Signing in…" spinner) — removes a double loader.
- **Splash floor of 2.5s** (`AppEnvironment.minSplashSeconds`), padded only when the auth check is faster — never adds delay on a slow network. Gives the brand a beat and the background warmup a head start.
- **Fixed + expanded warmup.** `startupDataWarmup` previously fetched briefing/dietary but never saved them (warmed nothing). Now it runs briefing + digest + dietary concurrently and SAVES each to SessionCache on a cache miss.
- **Services VM is now cache-first** for briefing/digest/dietary: a fresh cache entry (same-day / 8h) is authoritative — show instantly and SKIP the slow re-fetch (briefing ~26s, dietary ~46s). Eliminates the per-launch double-fetch; pull-to-refresh still clears cache for fresh data. (Deviation from §16 SWR for these three — documented there.)
- Build: ✅ success. Follow-up option: signup/OTP still use the branded loader (SignupView may have its own progress — revisit for consistency).

## [2026-08-08] Loader policy audit: scope, inline dashboard, tint backdrop

- **Backdrop reverted** to tint veil (`.ultraThinMaterial` @ 0.70) — the `.glassEffect(.clear)` pane looked wrong.
- **Audited every call for whether the loader is even visible.** The global loader renders behind `.sheet`, so all sheet-triggered calls now use `showsLoader: false` (HealthHub sheets: symptoms/measurements/meds/reports/periods/family; Services sheets: nutricheck/checkin/doctor/feed/workout/health-analysis; chat history + sidebar; profile edit/memories/family; paywall). Kept as full-screen blocker ONLY: auth (login/signup/OTP/bootstrap/loadProfile/pro-access/usage), HealthHub `getStats` ×2, Profile `relationships`.
- **Services dashboard → inline per-card loaders.** `ServicesHomeViewModel` now has per-card flags (isLoadingBriefing/Digest/Dietary/Feed/Workouts/Doctors/Analysis/CheckIn); each loader clears its own flag so a fast card no longer waits for the slowest (dietary ~45s). Added `InlineLoader` (small teal spinner) after each card heading. All dashboard reads set `showsLoader:false`.
- **Multipart:** `sendMultipart` gained `showsLoader:`; report upload is off (sheet shows its own state).
- Fixed arg-order compile errors (showsLoader must come after method/query/body). Verified 0 mis-ordered; build ✅.

## [2026-08-08] Loader: real Liquid Glass backdrop + context-aware messages

- **Glass backdrop** — `BrandedLoaderView` now uses actual Liquid Glass (`Rectangle().glassEffect(.clear, in: .rect)` over a faint `black.opacity(0.12)` scrim) instead of `.ultraThinMaterial` frost. Reads as glass ("liquid crystal"), not translucent blur. (Researched via Apple docs: `glassEffect(_:in:)`, `Glass.clear` needs a dimming layer beneath.)
- **Per-call messages** — `LoadingController` now holds a message stack; `Endpoint.loaderMessage` (+ `sendMultipart(loaderMessage:)`) sets the text; `RootView` shows `loader.message`. Every one of the ~82 network calls now has a specific, honest message (e.g. "Signing in…", "Saving medication…", "Analyzing your report…", "Generating your health analysis…"). Assigned across all service files (auth, health data, meds, reports, period logs, insights, AQI, doctors, family, feed, workouts, check-in, chat, payments).
- **Silent calls** — `showsLoader: false` added for background/fire-and-forget: analytics events, AQI store, NutriCheck feedback, and the report status poll loop (so the ~100s poll doesn't block; the sheet shows its own processing state). Chat send flow stays exempt (thinking bubble).
- Build: ✅ success.

## [2026-08-08] Apple Health measurements: UUID dedup + edit keeps provenance

Fixes: Apple imports duplicated on every sync; editing an import silently made it "manual". No backend change (backend has no unique key / source field).

- **`HealthKitManager`** — dedup via a persisted ledger of already-posted identities (`syncedKeys` in UserDefaults):
  - Point-in-time metrics use the **HealthKit sample UUID** (`sample.uuid`) — `latestQuantity` now returns it; `Reading` carries `dedupID`.
  - Aggregates (steps/active energy/sleep have no single sample UUID) use a **per-day key**; `todaySum`/`lastNightSleepHours` now return start-of-day so a day's total has one stable timestamp.
  - `saveAll` skips any reading whose `dedupID` is already in the ledger; ledger capped at 2000 entries.
  - `clearSyncState()` called from `AuthManager.logout` so the ledger doesn't cross accounts.
- **`MeasurementsSheetView.save`** — editing an Apple import now **re-sends the provenance sentinel**, so it stays grouped under Apple Watch instead of becoming manual.
- Caveat: on reinstall the ledger resets, so each current sample may re-post once (backend has no key to dedup against). Acceptable for the client-only approach.
- Build: ✅ success.

## [2026-08-08] Loader opt-out for chat + response-time logging

- **`Endpoint.showsLoader: Bool = true`** — per-call opt-out for the global branded loader. `APIClient.send` gates `begin()/end()` on it (defer kept at function scope).
- **Chat send flow exempted:** `ChatService.sendMessage` + first-send `createSession` pass `showsLoader: false` — the chat already shows a thinking bubble, so no full-screen blocker.
- **Response time in `[RH]` logs:** `APIClient` now stamps elapsed ms on every response, e.g. `← 200 /path (1234 bytes, 342ms)`; error/transport lines include it too. Added `ms(since:)` helper. Applies to `send` and `sendMultipart`.
- Build: ✅ success.

## [2026-08-08] Global branded loader for every REST call

- **`BrandedLoaderView.swift`** — Android `SimpleProgress` port: light glass veil (`.ultraThinMaterial` @ 0.55, touch-blocking) + native `GlassCard` with `AppLogo` spinning 0→360°/2s, message, teal "RichHealth AI". Spin via scoped `.animation(_:value:)` (no onAppear leak).
- **New `Core/LoadingController.swift`** — `@MainActor @Observable`, counter-based (`begin`/`end`/`isActive`) so concurrent calls share one loader and it clears only when the last finishes.
- **`APIClient.send` + `sendMultipart`** — `begin()` at start, `end()` in `defer` → loader shows before every call, hides on success OR failure.
- **`RootView`** — mounts `BrandedLoaderView` once via `.overlay` on the root Group; covers all screens. Fade in/out animation on `loader.isActive`.
- Removed the one-off test overlay in `HealthHubView` and the `.loadingOverlay(isActive: vm.isSaving)` in `ProfileView` (global now covers save) to avoid double-stacking. `LoadingOverlayModifier.swift` left in place but now unused by network flows.
- CLAUDE.md §26 rewritten to the global-loader decision (supersedes prior loading-by-intent draft). Build: ✅ success.

## [2026-08-08] Measurements: Apple/manual section polish

- **"Manually Added" section header** for non-Apple measurements (mirrors the Apple Watch group) — `square.and.pencil` teal icon + label.
- Apple Watch **count now brand-teal** (was secondary grey).
- Apple rows **genuinely shorter**: the real blocker was `List`'s 44pt default min row height — lowered via `.environment(\.defaultMinListRowHeight, 38)` + tight `.listRowInsets` on compact rows + reduced internal padding. Icon bumped 30→34 so it reads as consistent (a full 44 would force the row back to manual height — noted the icon-vs-height tradeoff to the owner).
- **CLAUDE.md C8** added: cosmetic tweaks must use native list/layout modifiers (`defaultMinListRowHeight`, `listRowInsets`, …), never fixed-frame hacks or custom components — don't fight the framework / over-engineer.

## [2026-08-08] Measurements: collapsible Apple Watch group + compact rows

Apple Watch imports (marked by `description == "Imported from Apple Health"`) are now split out of the main measurement list into their own **collapsible section** at the bottom (`Section(isExpanded:)`, collapsed by default, with a watch-icon header + count). Manual measurements stay as normal rows above.

### Changed
- **`DesignSystem/Components/HealthRecordRow.swift`** — removed the after-title `showsAppleWatchBadge` glyph; added a `compact` mode (30pt icon vs 44, `.subheadline` title, tighter vertical padding) for subtitle-less rows.
- **`Features/HealthHub/MeasurementsSheetView.swift`** — split `vm.filtered` into `manualItems` / `appleItems`; added a shared `measurementRow(_:compact:)` builder; Apple rows render compact with the **watch icon in the leading slot** (before the title, reusing the existing icon container) and no description → shorter height. Collapsible via `appleExpanded` state.

Build passes.

---

## [2026-08-08] Apple Watch provenance badge on measurements + edit-reverts-to-manual

Research first (§21, 3 agents): confirmed Apple Watch data **is** written into measurements — `HealthKitManager.saveAll()` POSTs each HealthKit reading to `POST /api/medical-data` as `type:"measurement"` with `description:"Imported from Apple Health"`. That description string is the only existing provenance marker. Backend `MedicalData` schema has **no** source field (strict mode drops unknowns) and Android has no source concept at all — so a schema change was avoidable. Chose iOS-only, reusing the existing sentinel (no backend/Android risk, no over-engineering).

### Changed
- **`Models/HealthDataModels.swift`** — `MedicalDataRecord` extension: `appleWatchSourceTag` constant (single source of truth for the sentinel), `isFromAppleWatch` (true while an unedited import), `displaySubtitle` (hides the sentinel from row subtitles).
- **`Core/Health/HealthKitManager.swift`** — sync now writes the sentinel via `MedicalDataRecord.appleWatchSourceTag` instead of a hardcoded string.
- **`DesignSystem/Components/HealthRecordRow.swift`** — added optional `showsAppleWatchBadge: Bool = false`; renders a compact `applewatch` glyph in `Theme.brandTeal` next to the title. Additive — the other 3 call sites (symptoms, meds, period logs) are unaffected.
- **`Features/HealthHub/MeasurementsSheetView.swift`** — row shows the watch badge (`item.isFromAppleWatch`) and uses `displaySubtitle` (hides the sentinel). Edit form: notes prefill strips the sentinel; `save()` now always sends `description` (empty string when blank) so editing overwrites the sentinel → the record reverts to a normal manual measurement (requirement #2). The metric type is already carried in `title` (Steps, Heart Rate, …), covering "which type of watch data."

Build passes. No backend or Android changes.

---

## [2026-08-08] Curved dark input editor + Richie composer drawer

### New
- **`DesignSystem/Components/DarkRoundedTextEditor.swift`** — single canonical curved, near-black long-form text editor (white text on `Theme.inputSurfaceDark`, `CornerRadius.card` corners, subtle hairline border, overlaid placeholder since `TextEditor` has no native prompt). Reused by both surfaces below so they stay identical (§2A one-pattern rule).
- **`Theme.inputSurfaceDark`** — fixed near-black field colour for these editors (owner request; documented as non-themeable, so a value not a material — keeps the §14 "no `Color(red:)` outside Theme" invariant intact).
- **`ComposerDrawerSheet`** (in `RichieView.swift`) — full-view typing drawer for Richie. Opens from a new expand button in the input action row, binds to `vm.input`, has a size toggle (principal toolbar) that switches the sheet between `.medium`/`.large` detents, Cancel, and a **Send** action. `.presentationDragIndicator(.visible)`.

### Changed
- **`Features/Profile/ProfileView.swift`** — `CustomInstructionsEditorSheet` now uses `DarkRoundedTextEditor` (was a plain grey `TextEditor`) — curved corners, near-black fill, white text, placeholder copy.
- **`Features/Richie/RichieView.swift`** — added `showComposer` state, an expand button (`arrow.up.left.and.arrow.down.right`) in the input action row (disabled when limit-blocked), and the composer-drawer sheet.

### Fixes / notes
- Expand button: final implementation is the **exact Custom Instructions sheet** (`ComposerDrawerSheet` = clone of `CustomInstructionsEditorSheet`, bound to `vm.input`), driven by `vm.showComposer` and presented as a 5th `.sheet(isPresented:)` on the ZStack using the **identical vm-Binding pattern as the 4 working sheets** (history/model/paywall/dependent). Earlier `@State`-driven attempts on odd hosts (safeAreaInset / NavigationStack / in-place toggle) were the wrong tree to bark up — matching the proven sheet pattern already on this screen is the fix.

- **Input-bar tap pass-through (the real root cause of the "expand doesn't work when focused / random taps"):** the bar sits in `.safeAreaInset` and the keyboard floats it over the empty-state suggestion cards. Its `VStack`+`.glassEffect` drew a background but didn't absorb touches, so taps fell through to the cards' `.onTapGesture` behind — the button animated but the card received the action. Fixed by adding `.contentShape(Rectangle())` to the whole bar (opaque hit target; child buttons still win their own taps). Pattern saved to memory.
- **Sluggish typing (real perf bug):** `chatInputBar` was a computed property inlined into `RichieView.body`, and it read `vm.input` (TextField + send-button disabled checks). With `@Observable`, every keystroke re-ran the WHOLE `RichieView.body` — rebuilding the empty-state ScrollView's 3 `.glassEffect` suggestion cards, the spinning logo and the message list on each character. Fixed by extracting the bar into its own `ChatInputBar: View` struct (`@Bindable var vm` + its own `isInputFocused`/`glowPulse`/`showUsageInfo`). Now a keystroke re-renders only the bar; the parent body no longer observes `vm.input`. Pattern saved to memory.
- **Log triage (NOT treated as fixes):** `persona…usermanagerd.xpc`, `RBSServiceErrorDomain "Client not entitled"`, `elapsedCPUTimeForFrontBoard`, `Reading from public effective user settings`, `variant selector cell index` = simulator / OS keyboard subsystem noise, not app-controllable and unrelated to the lag. `POST /api/analytics/event → 404` is a REAL finding but harmless to perf: `Analytics.track` is fire-and-forget (spawns a Task, swallows errors, no retry) and only fires on discrete actions (login, tab switch, send…), never per keystroke. The backend has no `/api/analytics/event` route — left as-is pending owner decision (don't remove analytics without approval).

### Pending (owner must apply — cannot edit project file safely while Xcode is open)
- **HealthKit crash**: app terminates with `NSHealthShareUsageDescription must be set`. Add the usage-description Info.plist key to the target (see chat for exact steps).
- Placeholder colour uses the semantic `.placeholder` style (not a hardcoded `.white.opacity`) — `TextEditor` has no native prompt param (confirmed via DocumentationSearch: only `text:` / `text:selection:`), so the overlay is the standard workaround.

Build passes.

---

## [2026-08-08] Legal & Privacy hub (glass bottom drawer)

### New
- **`Features/Legal/LegalHubSheet.swift`** — glass bottom-drawer hub launched from Profile → Settings → About → "Legal & Privacy". `.presentationDetents([.medium, .large])` + `.presentationBackground(.thinMaterial)` (§C5 glass). Contents: emergency guidance card + **all-in-app** documents (no external browser links) — Privacy Policy, Terms of Use, Medical Disclaimer, Support — each pushed via NavigationLink and rendered by a reusable `LegalDocumentView` (title + intro + sections + "Last updated"). Rows use `GlassCard` + teal icons + chevron, consistent with HubCard/DeviceSyncCard. `LegalInfo` holds support email + last-updated (⚠️ placeholder email; have Privacy/Terms text reviewed by counsel; App Store Connect still needs a hosted Privacy Policy URL in metadata).

### Changed
- **`Features/Profile/ProfileView.swift`** — added an "About" settings section with a "Legal & Privacy" row + `showLegal` sheet presentation.

Build passes. (Delete Account + the per-screen disclaimer footers from the checklist are still pending — separate follow-ups.)

---

## [2026-08-08] Analytics — first-party, privacy-safe event log

Owner-approved. Chosen approach: first-party (no third-party SDK) — lightest + safest for a health app. Strict rule: NO health data / PII, only event name + non-sensitive props + authenticated userId.

### Backend (richhealthbackend)
- **`models/Event.js`** (new) — `{ userId, name, props(Mixed), platform, appVersion, ts, createdAt }`; `createdAt` has a **180-day TTL** so the collection self-cleans.
- **`controllers/analyticsController.js`** (new) — `logEvents`: server-side event-name **whitelist** (must match iOS enum), `sanitizeProps` keeps only short primitives (drops objects/arrays; caps 12 props / 120 chars) as a hard guard against accidental PII/health data. Accepts single or batch; **always returns 200** (analytics never breaks the client).
- **`routes/analyticsRoutes.js`** (new) — `POST /api/analytics/event` + `/events` under `requireUser`.
- **`index.js`** — mounted at `/api/analytics`.

### iOS
- **`Core/Analytics/AnalyticsService.swift`** (new) — `Analytics.shared.track(_:_:)`, fire-and-forget via APIClient, never throws.
- Wired events (counts/ids only, never content):
  - Purchase funnel — `PaywallView`: paywall_view, subscribe_tap, purchase_success/failed, restore.
  - Feature usage — richie_message_sent (`RichieViewModel`, model only), nutricheck_run (`NutriCheckSheetView`), watch_synced (`HealthKitManager`, count), report_uploaded (`MedicalReportsSheetView`), checkin_completed (`CheckInSheetView`).
  - Screen views — `RootView` per tab (onChange initial:true).
  - Auth — login/signup_completed (`AuthManager`), logout (fired before token cleared).

### Compliance note
This collects **Usage Data / Product Interaction linked to identity** (userId). Must be declared in App Store Connect **App Privacy** and the privacy policy. No health data is collected by analytics (enforced by whitelist + prop sanitization). Full project build passes.

---

## [2026-08-08] Pro payments → StoreKit 2 IAP (resolves §10) + backend Apple verify

Owner approved building both sides (explicitly overriding CLAUDE.md §2 for the backend edit).

### iOS
- **`Core/Payments/StoreKitManager.swift`** (new) — shared `@Observable` StoreKit 2 manager. Loads products `richhealth.plus/pro/ultra`, `purchase()`, `restore()` (currentEntitlements), and a lifetime `Transaction.updates` listener for renewals. Every verified transaction's `jwsRepresentation` is sent to the backend.
- **`Core/Payments/PaymentService.swift`** (new) — `POST /api/payment/apple/verify { productId, transactionJWS }` → `{ success, plan, expiryDate }`.
- **`Features/Paywall/PaywallView.swift`** — replaced the "payment pending" TODO with real plan cards (App Store `displayName`/`description`/`displayPrice`), Subscribe buttons, Restore Purchases, loading/error states. On success → `auth.refreshProfile()` + dismiss.

### Backend (richhealthbackend)
- **`models/Transaction.js`** — added `appleTransactionId` (sparse unique), `appleOriginalTransactionId`, `appleProductId`, `source` enum `["razorpay","apple"]`.
- **`routes/paymentRoutes.js`** — added `POST /api/payment/apple/verify`.
- **`controllers/paymentController.js`** — `verifyApplePurchase`: verifies the signed transaction via `@apple/app-store-server-library` `SignedDataVerifier` (tries Production then Sandbox), checks bundle ID, maps productId→plan, idempotent Transaction upsert keyed on Apple txn id, then `activateAppleSubscription` (sets `isPro/proExpiryDate` **from Apple's expiresDate**/proSubscriptionPlan/lastTransactionId/proUpgradeDate). Read side (`/api/user/pro-access`, `/pro-status`) unchanged.
- **`package.json`** — added `@apple/app-store-server-library`.

### ⚠️ External setup required before it works (cannot be done in code)
1. **App Store Connect** — create 3 auto-renewable subscriptions with product IDs `richhealth.plus` (3mo), `richhealth.pro` (3mo), `richhealth.ultra` (1yr); sign Paid Apps agreement.
2. **Backend** — `npm install @apple/app-store-server-library`; add Apple root CA certs to `certs/apple/` (from apple.com/certificateauthority); set env `APPLE_BUNDLE_ID=richhealth.ai.richhealth` (+ `APPLE_APP_APPLE_ID` for production); redeploy.
3. **Testing** — use a **Sandbox** Apple ID on a real device (local `.storekit` file transactions are test-signed and won't pass server verification).

1. **Watch vitals cards empty (`Core/Health/HealthKitManager.swift`)** — `autoSyncIfNeeded` used to only refresh heart rate when throttled, leaving `readings` empty so SpO₂/Steps/Temp showed "—". Now it ALWAYS `fetch()`es (cheap on-device reads) on appear/foreground and throttles only the backend `saveAll()`. Auth request centralized in `ensureAuthorized()` (once/launch). Removed the now-dead `refreshHeartRate()`.
2. **Temp never populated** — Apple Watch records `appleSleepingWristTemperature` (overnight), not `bodyTemperature`. Added it to the read set and fall back to it for the Temperature reading.
3. **Dietary insights DECODE (`Models/ServicesModels.swift`)** — backend sometimes returns 200 without `foodsToEat`/`foodsToAvoid` (AI degraded). `DietaryInsightsResponse` now decodes defensively (missing arrays → empty), so the card shows its empty state instead of throwing a decode error. (The 503 itself is a transient backend outage, already surfaced as a handled error.)
4. **Location main-thread warning (`Features/Services/ServicesHomeViewModel.swift`)** — `CLLocationManager.locationServicesEnabled()` (blocking) was called on the MainActor. Now run via `Task.detached` off-main.

---

## [2026-08-08] Health Hub — live Watch vitals row + JSON logging

### Changed
- **`Features/HealthHub/HealthHubView.swift`**: when Apple Watch is connected, the top stat row shows **live vitals** (Heart · SpO₂ · Temp · Steps) under a "FROM APPLE WATCH" header (applewatch icon, uppercase §SectionLabel style) instead of the record-count chips (Symptoms/Vitals/Meds/Reports). Falls back to the record chips when not connected. New `WatchStatChip` mirrors `StatChip`'s footprint but takes a string value with `lineLimit(1)` + `minimumScaleFactor(0.6)` so cards stay identical height and never wrap. Auto-syncs on appear.
- **`Core/Health/HealthKitManager.swift`**: added `reading(_:)` accessor, a `readingsJSON` (pretty JSON of all readings), and `rhLog`-based logging of that JSON after every fetch (filter Xcode console by `[RH]`).

---

## [2026-08-08] Apple Health — auto-sync, Connected pill, heart rate everywhere

Made HealthKit sync automatic + periodic (no manual save), added a connection status pill, surfaced heart rate on the card and in Profile.

### Changed
- **`Core/Health/HealthKitManager.swift`** — now a shared singleton (`.shared`) + auto-syncing store. Added `sync()` (silent auth → read → auto-save all readings to backend), `autoSyncIfNeeded(minInterval:)` (throttled, default 15 min; refreshes just heart rate in between), `refreshHeartRate()`, and persisted `isConnected` + `lastSyncTS` (UserDefaults-backed, observable) plus `latestHeartRate`. Saving moved inside the manager (`saveAll`).
- **`App/RootView.swift`** — on foreground (`scenePhase == .active`, authenticated) calls `autoSyncIfNeeded()` → periodic sync.
- **`Features/Services/ServicesHomeView.swift`** — card auto-syncs on appear; `DeviceSyncCardView` now shows a **StatusPill** (green "Connected" / orange "Not connected", §12) and, once connected, the **latest heart rate** inline. No manual save button.
- **`Features/HealthHub/WatchSyncSheetView.swift`** — now a read-only status/detail sheet using `.shared`; auto-syncs on open; removed the manual Save button/selection.
- **`Features/Profile/ProfileView.swift`** — "At a Glance" stats now **Heart Rate | Air Quality | Weight | Sleep** (Water replaced by heart rate from HealthKit). Profile auto-syncs on appear.

### Note
The FIRST run still shows Apple's system permission sheet once (required by iOS — can't be skipped). After that, all syncing is silent and automatic.

---

## [2026-08-08] Moved Apple Health card Health Hub → Services

The Apple Health / Apple Watch card was initially placed in Health Hub, but Android's "Connect a Device" card lives in HomeFragment (the Services/home tab), which is where the owner expected it.

### Changed
- **`Features/Services/ServicesHomeView.swift`**: Added `DeviceSyncCardView` (GlassCard, 48×48 teal icon chip, "Apple Health" title, state-aware subtitle from `@AppStorage("healthKitLastSync")`, chevron) as card #3 (after Health Analysis). Opens `WatchSyncSheetView` via a `showWatchSheet` sheet.
- **`Features/HealthHub/HealthHubView.swift`**: Removed the "Devices" section + card, the `.watch` `HealthHubSheet` case, its sheet route, and the `@AppStorage`/`watchSubtitle` helpers. Health Hub is back to its prior sections.

`WatchSyncSheetView` + `HealthKitManager` are unchanged — only the entry point moved.

---

## [2026-08-08] Services cards — icon-chip size consistency audit

Audited the Services home cards vs the app's canonical patterns (GlassCard, StatusPill §12, `.skeleton`, HealthHub icon chip). Most dimensions already consistent (glass, chips, loading, timestamps, sheet detents). One concrete inconsistency fixed:

### Changed — `Features/Services/ServicesHomeView.swift`
- The teal icon chip on the Health Analysis and Check-In cards was `44×44 / 20pt`; HealthHub's `HubCard` uses `48×48 / 22pt`. Unified both Services chips to `48×48 / 22pt` so the same component renders identically across screens. Updated the stale comment (previously claimed "28pt icon in 44×44").

### Flagged, NOT changed (need owner call — avoiding scope creep)
- CheckIn sheet uses `.navigationBarTitleDisplayMode(.large)`; every other sheet uses `.inline`.
- Section-header teal usage: "Your Briefing" & "Health Feed" are `.primary` (they head multi-item sections, per §17), while single-card titles are teal. Defensible by type, but noted in case a single treatment is preferred.

---

## [2026-08-08] Health Hub — Apple Health / Apple Watch card + HealthKit sync

Native replacement for Android's Google Fit "Connect a Device" card (HomeFragment `watch_connect_card`, which read steps from Google Fit and only cached locally). iOS uses HealthKit (surfaces Apple Watch data) and goes further — it SAVES chosen readings to the backend.

### New files
- **`Core/Health/HealthKitManager.swift`** — `@MainActor @Observable`, read-only HealthKit. Requests authorization (read set), then fetches the latest value per metric: Steps + Active Energy (today cumulative sum), Heart Rate / Resting HR / Blood Oxygen / Body Temperature / Weight (latest sample), Blood Pressure (systolic+diastolic → "120/80"), Sleep (asleep hours over last 24h). Each `Reading` carries a `backendValue`/`unit`/`title` that maps onto the existing measurement schema.
- **`Features/HealthHub/WatchSyncSheetView.swift`** — deliberately dead-simple: opening the sheet auto-requests permission (`.task { connect() }`) and reads immediately; readings show; one "Save N to RichHealth" button saves them all via `HealthDataService.create` (`type:"measurement"`, description "Imported from Apple Health"). Stores last-sync in `@AppStorage("healthKitLastSync")`.
  - Edge cases: HealthKit unavailable → ContentUnavailableView; permission denied / read-status-hidden / prompt-never-appeared / no data → single empty state offering **Refresh** + **Open Settings** (HealthKit never reveals read-denial, so all "no data" cases are treated identically with a recovery path); partial save failure → "Saved X of Y" alert and stops. Blood pressure only emitted when both systolic+diastolic exist; SpO₂ fraction ×100.
- **`richhealth/richhealth.entitlements`** — HealthKit entitlement (`com.apple.developer.healthkit`).

### Changed
- **`Features/HealthHub/HealthHubView.swift`** — new "Devices" section with an `Apple Health` `HubCard` (icon `applewatch`) opening the `.watch` sheet; subtitle shows "Last synced …" from `@AppStorage` or "Sync heart rate, steps & more". Added `.watch` to `HealthHubSheet` and its sheet route.

### Backend
- Reuses `POST /api/medical-data` (one POST per reading — no batch endpoint exists). `title` is a free string, so metrics that match the existing 8 measurement types (Heart Rate, Oxygen Saturation, Temperature, Weight, Blood Pressure) integrate directly; Steps / Resting Heart Rate / Active Energy / Sleep save with their own titles. No backend changes.

### ⚠️ Requires two Xcode-UI steps (cannot edit project.pbxproj while Xcode is open — see below)
1. Target → Signing & Capabilities → **+ Capability → HealthKit** (links the entitlement + updates provisioning).
2. Target → Info → add **Privacy - Health Share Usage Description** (`NSHealthShareUsageDescription`). Without it the app crashes on authorization.
Until both are set, the card is present but the permission request won't function.

### Changes
- **`Features/Profile/ProfileView.swift`**: Kept the NATIVE `.segmented` `Picker` (real Liquid Glass is required) and switched its segments from text `Label`s to `Image(systemName:)` — so the Profile/Settings/Plan selector now shows icons (`person.fill`/`gearshape.fill`/`crown.fill`) with the stock glass. A text-only variant is left in place, commented out, for easy switching. The `.onAppear` `UISegmentedControl.appearance()` teal styling is unchanged.

### Why
Owner wants icons on the selector but native Liquid Glass is mandatory. Apple's segmented control renders a `Label` as text-only and `.palette` as icon-only — no native control does icon+text. A custom control was tried but only approximates the glass, so we stay native and use icon-only for now (text variant kept commented for evaluation).

### Reverted (earlier over-reach)
- Removed the custom `SegmentedTabSelector` view.
- Reverted the `richhealthApp.swift` `init()` that globally set `UISegmentedControl.appearance()` — restored the original per-view `.onAppear` block; other segmented pickers untouched.

---

## [2026-08-07] Richie suggestion card — bigger Ask/Not-helpful buttons

### Changes — `Features/Richie/RichieView.swift`
- Expanded suggestion card action row: "Ask" button `controlSize` `.small` → `.regular` with `.callout` label + extra horizontal padding; "Not helpful" bumped `.caption` → `.subheadline`. Row spacing `Theme.Spacing.m` → `.l` and added `.padding(.top, Theme.Spacing.xs)` for separation from the reasoning text.

### Note (not changed — needs owner OK)
Investigated the "1 symptoms / 1 measurement" grammar the owner reported. iOS pluralizes its own count strings correctly (`RichieViewModel.loadHealthSummary`, HealthHub uses count-only phrasing). The ungrammatical text originates in the BACKEND prompt `richhealthbackend/controllers/rhChatController.js:831` (DATA FOOTPRINT is count-first: "1 symptoms"), which primes the LLM and gets echoed into chat answers. Per CLAUDE.md §2, backend edits require owner confirmation — flagged, not yet fixed.

---

## [2026-08-07] Richie empty-state — match Android fragment_ai exactly

Read `../richhealth_android/.../res/layout/fragment_ai.xml` + `AIFragment.java` (§21) and corrected the iOS empty state to match:

### Changes — `Features/Richie/RichieView.swift`
- **Subtitle**: replaced "Your AI health companion" with the exact Android copy "Ask about your reports, symptoms or medications. I answer using what I know about you." (`.subheadline`, `.secondary`; Android 13.5sp / #5F6E6E).
- **Salutation**: `.largeTitle.bold()` → `.title.bold()` (Android welcomeGreeting is 25sp bold; largeTitle overshot).
- **Expanded suggestion card**: moved the `Divider()` to the TOP of the expanded section — directly under the question header row (matches Android `expand` divider `#152525`), instead of before the Ask/Not-helpful buttons. Reasoning now always shows with Android's fallback copy "Tailored to your profile and health data." when empty.
- **Toolbar**: swapped to match Android — chat-history button on `.topBarLeading` (LEFT), new-chat on `.topBarTrailing` (RIGHT). New-chat is now always visible (was gated on an active session). New-chat glyph → `square.and.pencil`.
- **Nudge card**: now a leading-icon · text · trailing `chevron.right` row (mirrors Android hint_box `ic_arrow_forward`); leading icon tinted `Theme.brandTeal`.

### Why
Owner flagged the iOS empty state diverged from the Android reference (divider placement, subtext copy, toolbar icon sides, nudge trailing arrow). Specs taken directly from the Android layout/Java, not assumed.

---

## [2026-08-07] Richie empty-state layout & input polish

### Changes
- **`Features/Richie/RichieView.swift`** (`emptyChatView`): Salutation/greeting enlarged from `.title2.bold()` to `.largeTitle.bold()`; header top margin bumped from `Theme.Spacing.l` to `Theme.Spacing.xl`. Reordered the empty state so the flow is salutation → "Suggested for you" section → nudge card. The nudge card (e.g. "add reports" hint) moved from above the suggestions to below them.
- **`Features/Richie/RichieView.swift`** (`chatInputBar`): Added `.padding(.vertical, Theme.Spacing.xs)` to the message `TextField` for a slightly taller input box.

### Why
Owner request for a bigger, better-spaced greeting and a clearer vertical rhythm (greeting on top, suggestions in the middle, contextual nudge below), plus a taller input field.

---

## [2026-08-07] Move Richie spinning-logo animation from toolbar to greeting

### Changes
- **`Features/Richie/RichieView.swift`**: Removed the perpetually rotating `sparkles` icon from the `.principal` toolbar. The principal slot now shows only the session title (when a session is active). Applied the continuous 6 s/rev rotation to the `Image("AppLogo")` that sits above the time-greeting/salutation in the empty state (`emptyChatView`). Uses a scoped `.animation(.linear(...).repeatForever(...), value: logoSpinning)` + `logoSpinning` bool toggled on appear — NOT `withAnimation` in `.onAppear`, which leaked the transaction into the sibling input bar's first layout (input box visibly expanded left-to-right on appear).
- **`CLAUDE.md` §18**: Updated the "Animated branding in feature headers" note to reflect the new location (greeting logo, not the toolbar) and dropped the idle/generating speed-switch (the empty state is never shown while the AI is generating).

### Why
Owner request: remove the always-moving star icon from the landing (Richie) screen's header and instead animate the logo icon above the greeting. The isSending speed variation is no longer meaningful because the empty state is replaced by the message list whenever a response is generating.

---

## [2026-08-07] Fix StatusPill plan badge styling + tab icon rendering

### Changes
- **`DesignSystem/Components/StatusPill.swift`**: Non-level pills (plan/label badges) now render as solid `Theme.brandTeal` background + white text, matching Android's filled teal capsule style. Level-based status pills keep the existing colored-text + translucent-background treatment for readability.
- **`Features/Profile/ProfileView.swift`**: Plan badge changed from `StatusPill(text:level:)` (green/yellow diagnostic styling) to `StatusPill(text: access.isPro ? "Pro" : "Free")` — no level, so it correctly uses the solid teal brand treatment.
- **`App/RootView.swift`**: Added `AppTab` enum and switched `TabView` to value-based selection (`Tab(..., value: AppTab.xxx)`) — the canonical documented pattern. Fixes missing tab icons for Health Hub, Services, and Profile tabs on iOS 26 Liquid Glass tab bar.

### Why
The plan badge was visually wrong (green text on light green background instead of the solid teal pill shown in Android). The tab icon issue was caused by using the unbound `Tab` API (`Value == Never`) which has a rendering quirk on iOS 26's new Liquid Glass floating tab bar — the value-based API is the Apple-recommended pattern.

---

## [2026-08-07] Fix edit profile save UX + Android SimpleProgress overlay equivalent

### Problem
Edit profile save failures were invisible: `saveError` was displayed as inline red text at the bottom of a 10-section scrollable `Form`. Users tapped Save, saw the sheet not close, and had no idea an error occurred unless they scrolled all the way down. `saveAIPreferences` used `try?` — silently swallowing all errors with no feedback.

### Root cause
`saveError` placement (bottom-of-form inline `Section`) is unreachable during normal interaction. Backend validation errors (Mongoose, duplicate email, 400 responses) were being thrown and caught but never surfaced to the user.

### Fix
- **`ProfileView.swift`** — Removed inline `saveError` Section from `EditProfileSheet`. Added `.alert("Couldn't Save Profile")` as a prominent modal — always visible regardless of scroll position. Changed toolbar Save button from conditional `ProgressView / Button` toggle to always-visible disabled button during save. Added `.loadingOverlay(isActive: vm.isSaving, message: "Saving profile…")` to form. Updated "Save AI Preferences" button to show inline `ProgressView` during save and disable re-tap. Added `.alert("Couldn't Save Preferences")` for AI save errors.
- **`ProfileViewModel.swift`** — Added `aiSaveError: String?` and `isAISaving: Bool`. Fixed `saveAIPreferences` to use `do/catch` instead of `try?`, capturing errors into `aiSaveError`. Added `isSaving` guard (`defer { isAISaving = false }`).
- **`DesignSystem/Components/LoadingOverlayModifier.swift`** (new) — Reusable `ViewModifier` that renders a full-screen semi-transparent overlay with `.thickMaterial` card, `ProgressView`, and a contextual message string. `allowsHitTesting(true)` blocks all interaction while active. iOS equivalent of Android's `SimpleProgress` dialog (ProfileFragment: "Saving profile…", "Tuning Richie to your preferences…"; HealthDataFragment: "Fetching your medications securely…" etc.). View extension: `.loadingOverlay(isActive:message:)`.

### Files changed

| File | Change |
|---|---|
| `richhealth/DesignSystem/Components/LoadingOverlayModifier.swift` | New — reusable loading overlay modifier |
| `richhealth/Features/Profile/ProfileView.swift` | saveError → alert; overlay on EditProfileSheet; AI save button loading state + alert |
| `richhealth/Features/Profile/ProfileViewModel.swift` | aiSaveError + isAISaving; saveAIPreferences do/catch |

---

## [2026-08-07] Full §25 screen audit — HealthHub + Profile + Services gap fixes

### Files changed

| File | Change |
|---|---|
| `Features/HealthHub/MedicationService.swift` | `discontinue()` now accepts `reason: String?` and `date: Date?`; encodes both into the PATCH body (`discontinueDate` + `reason`). Previously sent empty `{}`. |
| `Features/HealthHub/MedicationsSheetView.swift` | `MedicationsSheetViewModel.discontinue()` now passes collected reason + date to the service — the values from `DiscontinueMedicationSheet` were silently discarded before. |
| `Features/HealthHub/FamilySheetView.swift` | Added `editingRelationship: RelationshipRecord?` + `updateRelationship(_ record:, newRelationship:)` calling `PUT /api/user/relationship/edit`. Added swipe "Edit" action (indigo) on accepted connections. Added `EditRelationshipSheet` (`.medium` detent, wheel Picker) — mirrors Android `showEditRelationshipDialog()`. |

### Why
- Medication discontinue: Android sends `{ discontinueDate, reason }` in the PATCH body; iOS was sending `{}` — date/reason silently lost.
- Family edit relationship: Android item row has an edit button for accepted connections calling PUT `/api/user/relationship/edit`; iOS had no equivalent — only remove was available.
- §25 audit ran across HealthHub, Profile, Services tabs. AQI card (pollutant/temp/trend already present ✅), Profile habit sub-fields (not in backend iOS schema — skip), Feed item URL (no URL field in FeedItem model — backend gap).

---

## [2026-08-07] HealthHub gaps + FamilySheet dependent delete + MedicalReports trends chart

### Files changed

| File | Change |
|---|---|
| `Features/HealthHub/MedicationsSheetView.swift` | Replaced `.confirmationDialog` for discontinue with a proper `.sheet(item: $vm.discontinuingItem)` presenting `DiscontinueMedicationSheet` — reason TextField + optional DatePicker. `discontinuingItem: MedicationRecord?` replaces `confirmDiscontinueId: String?`. |
| `Features/HealthHub/FamilySheetView.swift` | Added `maxDependents: Int?` + `dependentCount: Int?` stored from `DependentsResponse`. Added `deleteDependent(_ id: String)` calling `DELETE /api/dependents/:id`. Dependents section now shows "Dependents (X/Y)" header counter. Dependent rows upgraded to teal icon + name/type VStack with swipe-to-delete action. |
| `Features/HealthHub/MedicalReportsSheetView.swift` | Added `showTrends` flag + Trends toolbar button (chart icon, disabled when empty). Added `ReportTrendsSheet`: groups `keyFindings` with `valueNumeric` by `canonicalKey`, selects test via Picker, shows latest/min/max/count stats row + optional reference range, Swift Charts `LineMark + AreaMark + PointMark` time-series with catmullRom interpolation — mirrors Android `dialog_report_trend_chart.xml` / `DialogUtils.java`. |

### Why
- `MedicationsSheetView`: `.confirmationDialog` can't collect form input; a sheet is the correct pattern for a reason + date form.
- `FamilySheetView`: Android `layout_family_members_panel.xml` shows dependent count against tier limit; delete was missing.
- `MedicalReportsSheetView`: Android `view_trends_button` opens `showReportTrendChartDialog()` — iOS equivalent was missing; added as a toolbar icon leading to a full trends sheet.

---

## [2026-08-07] Phase 6 — All Polish items (A–G)

### Files changed

| File | Change |
|---|---|
| `Features/HealthHub/MedicationsSheetView.swift` | Added orange `Label` disclaimer when `isOngoing == true` in Dates section — mirrors Android `dialog_add_medication.xml` yellow warning text |
| `Features/Richie/RichieViewModel.swift` | Added `healthSummary: String?`; `loadHealthSummary()` fetches `MedicalDataStats` + `MedicationStats` in parallel in `load()`, builds a context line |
| `Features/Richie/RichieView.swift` | Shows `vm.healthSummary` in teal below "Your AI health companion" in empty state |
| `Features/HealthHub/FamilySheetView.swift` | Toolbar `+` button changed to `Menu` with two options: "Connect Family Member" (existing `AddFamilyMemberView`) and "Add Dependent" (new `AddDependentView`). Added `addDependent()` VM method posting to `POST /api/dependents`. Added `AddDependentView` form with name, type, gender, DOB |
| `Features/Services/DoctorSheetView.swift` | Added `disclaimerDoctor: DoctorSearchResult?`; Connect button now calls `vm.showDisclaimer(for:)` instead of directly connecting; `.confirmationDialog` shows data-sharing disclaimer before confirming |
| `Models/ServicesModels.swift` | Added `CheckInListResponse`, `CheckInSessionRecord`, `CheckInResponseRecord`, `CheckInStartResponse`, `CheckInQuestion`, `CheckInOption`, `CheckInRespondRequest`, `CheckInRespondSessionInfo`, `CheckInRespondResponse` |
| `Features/Services/CheckInSheetView.swift` | New file — full daily check-in flow: session list, status badges (StatusPill), accordion for completed sessions with response rows, Swift Charts bar chart (completed/missed/in-progress), question flow with 2-column `OptionCard` grid, progress bar, Next/Done button, "All caught up" empty state |
| `Features/Services/ServicesHomeView.swift` | `CheckInPlaceholderSheet()` → `CheckInSheetView()`. Removed dead `CheckInPlaceholderSheet` struct |

### Why
- Medication disclaimer parity with Android `dialog_add_medication.xml` yellow warning
- Richie health context line mirrors Android's `showHealthDataContext()` in `AIFragment.java`
- Family two-button split matches `layout_family_members_panel.xml` Add Dependent + Connect Family Member separation
- Doctor disclaimer matches Android `showConnectionDisclaimerDialog()` in `HealthDataFragment.java`
- CheckIn full flow replaces Phase 6 placeholder — parity with `DailyCheckInActivity.java` (session list, question flow, bar chart, "not yet due" state, resume logic)

---

## [2026-08-07] Visual polish — round 2: briefing timestamp, icon consistency, usage ring tap

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Services/ServicesHomeViewModel.swift` | Added `var briefingGeneratedAt: String?`; populated in `loadBriefing()` from both cache and fresh fetch. |
| `richhealth/Features/Services/ServicesHomeView.swift` | `BriefingSectionView` gains `generatedAt` param; shows relative time ("Xm/h/d ago") in header HStack trailing. `HealthAnalysisCardView` header restructured from `Label("Health Analysis", …)` to `ZStack` icon container (44×44, teal 0.12 bg, 20pt icon) + `VStack(title + StatusPill)` — matches CheckIn card icon treatment to remove inconsistency. |
| `richhealth/Features/Richie/RichieView.swift` | Usage ring wrapped in `Button` with `.popover` showing "X of Y messages used · Z left this session" — mirrors Android usage toast. Added `@State showUsageInfo`. |

### Why
- Briefing card had no timestamp; all other primary cards now show when data was last updated.
- HealthAnalysis card used a tiny inline Label icon while CheckIn had a prominent 44×44 container — visible inconsistency.
- Usage ring was not tappable; Android shows a toast with the count; iOS equivalent is a popover.

---

## [2026-08-07] Visual polish — Richie glow, suggestion alignment, service timestamps, profile border fix

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Richie/RichieView.swift` | Toolbar icon changed from `Image("AppLogo")` to `Image(systemName: "sparkles")` — eliminates double-logo with the empty-state body logo. Added `@FocusState isInputFocused` + `@State glowPulse` for dynamic input border: soft teal when focused, pulsing teal glow when AI is generating (`isSending`). Pulse implemented via `.task(id: vm.isSending)` loop toggling `glowPulse` every 800ms with `.easeInOut` animation. Suggestion card action row fixed: "Ask" + "Not helpful" now left-aligned together (`HStack(spacing: Spacing.m)` + trailing `Spacer()`), matching Android layout. |
| `richhealth/Features/Services/ServicesHomeView.swift` | Added `relativeTime(_:)` private file-scope helper (ISO 8601 → "Xm/h/d ago"). Health Analysis card shows timestamp ("Updated X ago") from `HealthAnalysis.lastUpdated`. Check-In card shows "Last: X ago" from `lastCompletedAt` in the trailing VStack. |
| `richhealth/Features/Profile/ProfileView.swift` | Completion border: changed from ZStack sibling overlay (which was clipped by List insetGrouped section rounded-rect clip, showing only vertical lines) to `.overlay { }` directly on `GlassCard` — trim border now renders within the card's own layout bounds and displays correctly. Stroke inset increased to `padding(2)` to ensure the 2.5pt stroke is fully inside bounds. |

### Why
- Double logo (toolbar AppLogo + body AppLogo) was redundant and visually noisy. CLAUDE.md §18 specifies the Richie tab uses a rotating sparkles icon in the toolbar.
- Input card had no visual feedback during AI generation. Android's `updateInputBorder()` changes stroke color/width dynamically; iOS now matches with the glow pulse ("boundy") effect.
- Suggestion card "Ask" and "Not helpful" were separated by a Spacer, making "Not helpful" appear right-aligned. Android puts both left-aligned with a gap.
- Service cards were missing the "Updated X ago" timestamps that Android HomeFragment shows on Health Analysis and Check-In cards.
- Profile completion border showed as two straight vertical lines — List insetGrouped clips section content to its own rounded rect, cutting off the horizontal edges of the trim border. Overlay-on-GlassCard keeps the trim within the view's own clip.

---

## [2026-08-07] Profile tab & usage drawer redesign

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Profile/ProfileView.swift` | Restored 3-tab picker (Profile \| Settings \| Plan). Profile completion ProgressView replaced with `RoundedRectangle.trim()` border stroke on the header card — clockwise from top, teal at 55% opacity, 2.5pt. "Tap Edit to complete" → "Add missing info" button with callback that opens EditProfileSheet. `ProfileHeaderView` gains `onFillProfile` callback param. `UsageRingItem` ring removed — plain list row with `Text("\(pct)%")` colored by level (§C7). `UsageFullSheet` changed from `List` to `ScrollView + VStack`. `UsageFullRow` replaced with `GlassCard` + trim border (same design token as profile card) so every usage item shows its fraction as a border fill. |
| `richhealth/App/AppEnvironment.swift` | `bootstrap()` fires `startupDataWarmup()` in background after auth succeeds. Pre-fetches briefing (daily TTL) and dietary insights (8h TTL) into SessionCache while splash is active — Services tab shows data instantly on first navigation. |

### Why
- Profile tab was showing only Settings + Plan since last session's fix; user info (Personal Info, Physical, Fitness etc.) was missing.
- ProgressView inside card was visually inconsistent with the glass design system.
- Circular UsageRing in usage drawer was redundant and inconsistent with the rest of the list.
- Splash screen should use idle network time productively (smart loading pattern).

---

## [2026-08-07] Splash screen + biometric lock

### Files changed

| File | Change |
|---|---|
| `richhealth/Core/Auth/BiometricManager.swift` | NEW — `@Observable @MainActor` class using `LocalAuthentication`. `lockIfEnabled()` gates on UserDefaults `rh.biometricEnabled`. `authenticate()` calls biometrics with passcode fallback on `.biometryLockout`. `verifyForSetup()` used by profile toggle — reverts if user cancels. |
| `richhealth/App/SplashView.swift` | NEW — branded splash (black bg, AppLogo spring scale 0.65→1.0, "RichHealth" + tagline fade-in, RichLabs footer). Also contains `BiometricLockScreen` (`.ultraThinMaterial` overlay, auto-triggers Face ID on `.onAppear`, retry button stays visible on cancel). |
| `richhealth/App/AppEnvironment.swift` | Added `let biometric = BiometricManager()`; `Phase` enum is now `Equatable` for `.animation(value:)`. |
| `richhealth/App/RootView.swift` | `.launching` → `SplashView()` instead of `ProgressView()`. `.authenticated` tab shell gets `BiometricLockScreen` overlay (animated `.opacity` transition). Added `@Environment(\.scenePhase)` observer: `.background` → `lockIfEnabled()`. Smooth `.easeInOut(0.3)` between phases. |
| `richhealth/Features/Profile/ProfileView.swift` | Biometric toggle now calls `verifyForSetup()` on enable — reverts if Face ID fails/cancelled. `.disabled(!appEnv.biometric.canUseBiometrics)` greys out on devices without biometrics. |

### Why
- Android `SplashActivity.java` shows a branded launch screen (~3500ms minimum delay). iOS native approach: splash duration = exactly how long `bootstrap()` takes — no artificial delay. Spring animation mirrors Android's ObjectAnimator scale.
- Android `BiometricHelper.java` implements lock/unlock but iOS had no equivalent — toggle existed in UI but was completely unimplemented (no `LocalAuthentication`, no `scenePhase` observer, setting was ignored).
- Manual step required: add `Privacy - Face ID Usage Description` key to Xcode target Info tab (value: "RichHealth uses Face ID to protect your health data.") — cannot be done via code without editing pbxproj while Xcode is open.

---

## [2026-08-07] Plan tab — add MEMBERSHIP section (family coverage)

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Profile/ProfileViewModel.swift` | Added `relationships`, `isFamilyPlanOwner`, `familyProMemberCount`, `maxFamilyMembers` properties; `load()` now fetches `GET /api/users/relationships` in parallel with pro/usage fetches; added `removeFamilyMember(userId:)` calling `POST /api/payment/family-member/remove` |
| `richhealth/Features/Profile/ProfileView.swift` | Added MEMBERSHIP section to `planContent()`: subscription summary row (bolt icon + plan name + "N/max covered" StatusPill), ForEach of relationship rows (person icon + name/email + COVERED/PRO StatusPill + red Remove button for owners), empty state label |

### Why
- Android Plan tab screenshot shows a MEMBERSHIP section with family plan summary and per-member rows
- Relationship data available from `GET /api/users/relationships` (RelationshipsResponse already in HealthDataModels.swift)
- Remove endpoint confirmed as `POST /api/payment/family-member/remove`

---

## [2026-08-07] Fix HealthDataModels decode failures — resilient inits for all record and stats types

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/HealthDataModels.swift` | `MedicationStats.recentMedications`, `MedicalDataStats.recentItems/commonSymptoms` made optional; `StatsBody` inits default missing counts to 0; `MedicationRecord`, `MedicalDataRecord`, `PeriodLogRecord` get resilient `init(from:)` via extension (preserves memberwise init for placeholders); `MedicalDataListResponse.pagination` and `PeriodLogsListResponse.pagination` made optional |
| `richhealth/Features/HealthHub/HealthHubViewModel.swift` | `s.recentItems ?? []` after making the field optional |

### Why
- `GET /api/health/medications/stats` — "data is missing" (`keyNotFound`) thrown by Swift decoder
- Root cause: any non-optional field absent in the JSON kills the whole struct decode; `shareWithFamily`, `includeInChat`, `flowIntensity`, `painLevel` in record types can be absent in older backend documents; `recentMedications`/`recentItems` can be omitted when count is 0; `StatsBody` count fields can be missing
- Fix: custom `init(from:)` in extensions (preserves memberwise init used by placeholders) with `?? default` for each required-but-potentially-absent field; stats arrays made optional; pagination made optional

---

## [2026-08-07] Fix UserProfile JSON decode failure — resilient custom init(from:)

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/UserProfile.swift` | Added custom `init(from decoder:)` — uses `try? c.decode(...)` for every optional field; Int/Number fields also try Double fallback |

### Why
- `GET /api/user/profile` returned 200 with 43KB body but Swift threw a fatal decode error
- Root cause: one or more backend fields sent an unexpected JSON type (e.g. Mongoose `Number` stored as float, or `ObjectId` reference serialized as an object instead of string)
- Targeted single-field fixes (`weeklyGoal: String?` → `Int?`) were insufficient — there are multiple mismatches
- Fix: custom `init(from:)` using `try? c.decode(T.self, forKey:)` for all optional fields — missing key and type mismatch both produce `nil` instead of crashing the entire struct decode
- Only `id` (`_id`) is required and can still throw; all other fields gracefully degrade to nil

---

## [2026-08-07] Family selector, CheckIn CTA, AQI logging, settings icons & custom instructions popup

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/ChatModels.swift` | Added `DependentEntry`, `DependentsListResponse`; added `dependentId` to `CreateSessionRequest` |
| `richhealth/Features/Richie/ChatService.swift` | Updated `createSession(dependentId:)`; added `getDependents()` → `GET /api/dependents/users` |
| `richhealth/Features/Richie/RichieViewModel.swift` | Added `dependents`, `selectedDependent`, `showDependentPicker`; `loadDependents()` called in `load()` in parallel; `send()` passes `dependentId`; `startNewChat()` resets selection |
| `richhealth/Features/Richie/RichieView.swift` | Added dependent picker pill in input action row (locked after session starts); added `.confirmationDialog` for family member selection |
| `richhealth/Features/Services/ServicesHomeViewModel.swift` | Added `rhLog()` throughout `loadAQI()` at each decision point |
| `richhealth/Features/Services/ServicesHomeView.swift` | `CheckInCardView` now takes `onTap` callback, shows action button (Continue/Start/View History) based on state, tappable whole card; added `CheckInPlaceholderSheet` (Phase 6 placeholder); wired `showCheckInSheet` state |
| `richhealth/Core/Auth/AuthManager.swift` | Added `rhLog()` to `bootstrap()` and `loadProfile()` to trace authentication and field loading |
| `richhealth/Features/Profile/ProfileView.swift` | Settings tab: all rows now use `Label` with consistent `.secondary` icons; `TextField` for custom instructions replaced with `Button` opening `CustomInstructionsEditorSheet`; added `CustomInstructionsEditorSheet` struct |

### Why
- Chat input was missing Android `inputProfileChip` family member selector; `dependentId` goes at session creation
- `CheckInCardView` had no tap action and no CTA button — looked broken
- AQI location failures were silent; `rhLog()` added at every decision point to diagnose via `[RH]` filter
- Settings had only one icon (`AI Memory`) while others had none; some icons appeared accent-colored inconsistently
- Custom instructions `TextField` inline in a List row was cramped; sheet gives full editing space

---

## [2026-08-07] Richie + Profile bug fixes — accordion, toolbar, input bar perf, completionPercent

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Richie/RichieView.swift` | Accordion suggestions (collapsed by default, onTapGesture expands one at a time); toolbar shows session title when chat active (no more "Richie" text + logo side-by-side); input bar background changed from `.ultraThinMaterial` (blur, slow focus) to `Color(.secondarySystemBackground)` (opaque, native, fast) |
| `richhealth/Features/Profile/ProfileView.swift` | Fixed `completionPercent` bug: was treating 0–1 fraction as 0–100% (showed "0%" always, nearly-invisible progress bar); now correctly multiplies by 100 for display and passes raw fraction to ProgressView |

### Details

**Richie suggestion cards (accordion)**
- Added `@State private var expandedSuggestionID: UUID?` to RichieView
- Cards start collapsed (question + chevron only)
- Tap card → expands (shows `why` text + "Ask Richie" + "Not helpful" buttons); tap again → collapses
- Only one card open at a time — tapping a different card opens it
- Inner buttons capture their own taps (SwiftUI Button > onTapGesture priority); tapping blank space/question text toggles the card

**Richie toolbar**
- Removed hardcoded `Text("Richie")` next to spinning AppLogo — was visually doubled with the big logo in empty state body
- When `vm.currentSession?.title` is non-nil and non-empty, shows the session title next to the spinning logo
- When no active session (empty state), shows only the spinning logo

**Input bar performance**
- `.ultraThinMaterial` on a container wrapping a TextField causes UIVisualEffectView blur to recalculate on every scroll and focus event → significant typing lag
- Replaced with `Color(.secondarySystemBackground)` — opaque, adaptive system color, zero blur overhead
- Reduced shadow radius 12→4 for additional compositing savings

**Profile completion bar**
- `UserProfile.completionPercent` returns `Double` in range 0.0–1.0 (fraction of 14 filled fields)
- Previous code checked `pct < 100` (always true) and passed `pct / 100.0` to ProgressView (nearly zero)
- Fix: `fraction = completionPercent`, `pct = fraction * 100` for display text, `ProgressView(value: fraction)` for the bar

---

## [2026-08-07] §25 Profile tab audit — UI fixes, completion bar, grid→list, logout confirm

### Files changed

| File | Change |
|---|---|
| `Features/Profile/ProfileView.swift` | Profile completion bar; usage rings grid→list; AI settings pickers; logout confirmation |

### What changed

**Profile completion bar** — Added below the 4-stat "At a Glance" row in `ProfileHeaderView`. Shows percentage (`user.completionPercent`) + teal progress bar. Hidden when profile is 100% complete. Mirrors Android's `completenessRing` + `completenessPercent` in the profile header.

**Usage rings: grid → list rows** (§18 fix) — Replaced `LazyVGrid(2 columns)` in Plan tab with plain conditional `if let` children directly inside the `Section`. Each `UsageRingItem` now renders as a horizontal `HStack` (ring 28×28 | label+count | limit pill) instead of a vertical centered cell. Text-heavy content belongs in full-width rows, not grids.

**AI & Chat settings pickers** — Replaced the dense VStack+label+segmented pattern for Response Tone and Reply Length with plain `Picker` rows. In a `List.insetGrouped`, `Picker` renders natively as a LabeledContent-style row with the current value on the right — clean, less vertical space, more iOS-idiomatic.

**Logout confirmation dialog** — Added `@State private var showLogoutConfirm`. Logout button now sets `showLogoutConfirm = true` → triggers a `.confirmationDialog` ("Log out? You'll need to sign in again…") with a destructive confirm action. Matches Android's `DialogUtils.showConfirmDialog()` before logout.

### Why
User reported profile screen as "broken, a lot of not so good looking UI." Root causes: 2-column usage grid violated §18 density rule; segmented pickers inside list cells were non-native and space-wasting; no profile completeness feedback; immediate logout without confirmation is a destructive-action UX risk.

---

## [2026-08-07] Richie screen — floating input bar, suggestion card redesign, UsageRing size fix

### Files changed

| File | Change |
|---|---|
| `Features/Richie/RichieView.swift` | Restructured input bar into single floating glass card; redesigned suggestion cards; reduced UsageRing |

### What changed

**Input bar** — Replaced the two-row flat layout (model pill row + text field row) with a single rounded floating glass container (`.ultraThinMaterial`, corner radius 22, shadow). Text field is at the top; action row (model pill · usage ring · Aa · send) is below inside the same card. Matches Android's `MaterialCardView` input container and ChatGPT-style floating pill.

**UsageRing** — Reduced from 22×22 to 16×16. The ring is a compact usage indicator, not a prominent feature — Android uses 18×18 inside a 30×30 tap target; iOS equivalent is 16×16.

**Suggestion cards** — Redesigned from "tap the whole card to send + X button outside" to proper card layout: bold question title + secondary hint/why text + "Ask Richie" (`.bordered`, teal) button + "Not helpful" (plain, secondary) button at bottom. Matches Android's expanded accordion state (iOS shows all cards fully expanded — no accordion needed). Cards remain hidden once any message exists (`vm.messages.isEmpty` guard in parent).

### Why
User feedback with screenshots: input bar looked flat/inline rather than floating; UsageRing was visually too large; suggestion cards were missing the proper hint text + action button layout that Android shows.

---

## [2026-08-07] §25 Services tab audit — Health Analysis, Check-In, UX fixes vs Android HomeFragment

### Files changed

| File | Change |
|---|---|
| `Models/ServicesModels.swift` | Added `HealthAnalysis`, `HealthAnalysisResponse`, `CheckInHomeCardResponse` models with nested types, computed status levels, and change summaries |
| `Features/Services/HealthAnalysisService.swift` | **New** — `GET /api/health/analysis` + `POST /api/health/analysis/generate`; generate uses 150s-timeout URLSession (Android uses 120s) |
| `Features/Services/HealthAnalysisSheetView.swift` | **New** — Full analysis sheet: status chip + headline + profile completion bar, per-type tab strip (Overall/Symptoms/Vitals/Medications/Reports/Genetics), data-changes banner, profile snapshot, generate/refresh button, empty state |
| `Features/Services/ServicesHomeViewModel.swift` | Added `healthAnalysis`, `checkIn`, `isGeneratingAnalysis` state; added `.healthAnalysis` sheet case; added `loadHealthAnalysis()`, `loadCheckIn()`, `generateAnalysis()` — all run in parallel with existing loaders |
| `Features/Services/ServicesHomeView.swift` | Added `HealthAnalysisCardView` (status + headline + generate CTA); `CheckInCardView` (state badge); fixed `DigestCardView` to show inline AQI chip when `showAqi == true`; fixed Doctor section button to say "Find Doctor" (empty) vs "Manage" (connected) |

### Why
Android `HomeFragment.java` has a Health Analysis card that is one of the most prominent features — it drives Pro upgrades and is the central health insight screen. It was entirely missing from iOS. Similarly, the Daily Check-In card was missing.

Android shows an AQI chip inline in the daily advisory when `showAqi == true` — the iOS `DailyDigestResponse` model already had the `showAqi`/`aqiValue` fields but the view was ignoring them.

Doctor button in Android changes label based on connection state — iOS was always showing "Connect".

### Architecture notes
- `HealthAnalysisService` uses a separate `APIClient` instance with 150s timeout for `generate` (POST /api/health/analysis/generate can take up to 2 minutes per Android source)
- `HealthAnalysisSheetView` is self-contained with its own generate capability; parent VM refreshes on next `.task` load
- Check-In card shows status from `GET /api/checkin/home-card`; full check-in flow is a separate phase

---

## [2026-08-07] §25 HealthHub audit — gap-fill vs Android HealthDataFragment

### Files changed

| File | Change |
|---|---|
| `Models/HealthDataModels.swift` | Added `includeInChat: Bool = true` to `CreateMedicationRequest` and `CreatePeriodLogRequest` (was missing; models had it on the record side but not the request side) |
| `Features/HealthHub/SymptomsSheetView.swift` | Fixed severity scale from 1–10 → 1–5 (matches Android SeekBar); updated `severityLabel`/`severityLevel` helpers; added `shareWithFamily` + `includeInChat` toggles to form; prefill reads both fields from existing record |
| `Features/HealthHub/MeasurementsSheetView.swift` | Added `shareWithFamily` + `includeInChat` toggles to form; prefill + save updated |
| `Features/HealthHub/MedicationsSheetView.swift` | Added `shareWithFamily` + `includeInChat` toggles to form; prefill + save updated (request now sends both fields) |
| `Features/HealthHub/PeriodLogSheetView.swift` | Added `shareWithFamily` + `includeInChat` toggles to form; prefill + save updated |
| `Features/HealthHub/HealthHubView.swift` | Fixed period card visibility: now checks menstrual status in addition to gender (matches Android `if gender == Female OR menstrualStatus not in [not_applicable, prefer_not_to_say]`); added 4th Reports StatChip to stats row |
| `Features/HealthHub/FamilySheetView.swift` | Added Pro/Covered plan badges to FamilyRow (from `RelationshipRecord.isPro` and `isCoveredByMyPlan` which were in the model but never displayed) |

### Why
Android `HealthDataFragment` side panels all have `SwitchMaterial` toggles for `shareWithFamily` and `includeInChat` in every add/edit dialog — these were absent from all iOS forms despite the backend models carrying those fields.

Android `HealthDataFragment.java` visibility check for period card: `if (gender.equals("Female") || (menstrualStatus != null && !menstrualStatus.equals("not_applicable") && !menstrualStatus.equals("prefer_not_to_say")))` — iOS was only checking gender.

Android `dialog_add_symptom.xml` uses a SeekBar(1–5) with explicit labels "Very Mild/Mild/Moderate/Severe/Very Severe". iOS was using a 1–10 Slider causing cross-platform inconsistency in stored severity values.

`RelationshipsResponse` carries `isPro` and `isCoveredByMyPlan` per member but FamilyRow was ignoring them; Android shows plan status badges.

---

## [2026-08-07] §25 RichieView audit — gap-fill vs Android AIFragment

### Files changed

| File | Change |
|---|---|
| `Features/Richie/RichieViewModel.swift` | Added `messagesUsed`/`messageLimit` tracking; `suggestionsBackup` pool; `chatFontSize`/`cycleChatFontSize()`/`chatFontSizeLabel`; `dismissSuggestion(id:)`; `.monthlySessionLimit` ChatLimitKind case; updated `send()` to track usage; updated `handleSendError` to distinguish monthly vs per-session limit; updated `loadSuggestions()` to split 3 display + backup pool; fixed `deleteSession` result discard |
| `Features/Richie/RichieView.swift` | Time-aware greeting ("Good morning [name]") in empty state; nudge icon chosen by `nudge.type` (6 icon types); "Not helpful" × dismiss on each suggestion card (swaps from backup); usage ring in input bar when usage data available; Aa text size button in input bar; replaced `TypingIndicatorView` dots with `ThinkingIndicatorView` (5 rotating phrases escalating every 8s); separate `monthlyLimitBanner` (cannot start new chat, upgrade CTA); richer `sessionLimitBanner` (upgrade button added); history sheet: `.searchable` search bar, time-ago on rows, message count on rows; `ChatBubbleView` now respects `fontSize` from ViewModel |

### Gap analysis findings (from §25 3-agent audit)

**Fixed (11 of 13 gaps):**
1. Time-aware greeting + user name (Android `showWelcomeMessage()`)
2. Nudge icon by type (add_measurements/add_symptoms/add_family/freshness/add_reports/add_meds)
3. "Not helpful" dismiss per suggestion with backup pool swap
4. Usage ring (circular) in input bar
5. Aa text size cycle (Small 13pt → Medium 14pt → Large 16pt)
6. Thinking text rotation ("Thinking…" → "Still thinking…" → "Working through your data…" etc.)
7. Monthly session limit — separate banner with correct copy (cannot start new chat)
8. `messagesUsed`/`messageLimit` tracked from `SendMessageResponse`
9. History search bar (`.searchable`)
10. History rows: time-ago display + message count
11. `.monthlySessionLimit` ChatLimitKind case distinct from `.monthlyOrRate`

**Deferred (require cross-feature work or owner decision):**
- Fork feature (branch conversation) — needs backend endpoint confirmation
- Health quick-log cards in chat — needs HealthHub integration first
- Saved messages panel — needs GET `/api/chat/saved-messages` verification
- Dependent/family profile selector — needs Dependents feature built first

---

## [2026-08-07] §25 Profile screen audit — complete ProfileView rewrite + model/VM updates

### Files changed

| File | Change |
|---|---|
| `Models/UserProfile.swift` | Added 4 missing backend fields: `familyHistoryRelatives`, `medicationCategories`, `weeklyGoal`, `recentWeightChange`; added `AIMemory` + `AIMemoriesResponse` types for `GET /api/user/memories` |
| `Features/Profile/ProfileViewModel.swift` | Added `showMemorySheet`, `showChangePassword`, `showFullUsage`, `cachedAQI`, `memories`, `isLoadingMemories`, `isMetric` (UserDefaults), `biometricEnabled` (UserDefaults), `aiAutofillCards`; added `loadCachedAQI()`, `loadMemories()`, `deleteMemory()` methods; updated `syncAIPrefs` + `saveAIPreferences` for `autofillCards`; fixed discarded-result warning on delete |
| `Features/Profile/ProfileView.swift` | **Full rewrite** — see details below |

### ProfileView.swift rewrite details

**Header (ProfileHeaderView):**
- Replaced BMI stat column with AQI (from SessionCache, shown as "Air Quality") — BMI was invented, not in Android `fragment_profile.xml`
- Stats order now matches Android: Air Quality · Weight · Sleep · Water

**Profile tab — section reorganization:**
- Personal Info: Email (new), Age, Gender, Phone, Location, Occupation (moved from Lifestyle), Ancestry/Ethnicity
- Physical: Height, Weight, Waist, Blood type, Recent Weight Change (new backend field)
- Fitness & Goals: Primary goal, Weekly goal (new backend field), Activity level, Diet type
- Lifestyle: Sleep, Water, Meals, Stress, Screen time, Sun exposure (Occupation removed — moved up to Personal Info)
- Habits: Smoking, Alcohol, Caffeine
- Medical (chips): Conditions, Allergies, Medication types (new backend field) — displayed as teal Capsule chips via `FlowLayout` + `ProfileChipsRow`
- Family History (new section): Family history chips, Affected relatives chips (new backend field)
- Reproductive Health: all existing rows + Cycle symptoms as chips; conditional on gender Female/Other or non-null menstrual status

**Settings tab additions:**
- AI & Chat: added Quick-log cards toggle (`aiAutofillCards`), AI Memory management row (opens `MemoryManagerSheet`)
- NEW General section: Notifications row (opens App-Prefs URL), Metric units toggle (`isMetric`)
- NEW Security & Privacy section: Biometric lock toggle (`biometricEnabled`), Change password button (opens `ChangePasswordSheet`), Share progress (`ShareLink`)

**Plan tab:**
- Added "View full usage" row that opens `UsageFullSheet`

**New private structs:**
- `FlowLayout: Layout` — wrapping chip layout using iOS 16+ Layout protocol
- `ProfileChipsRow` — icon + label + FlowLayout of teal Capsule chips
- `MemoryManagerSheet` — lists/deletes `AIMemory` records via `DELETE /api/user/memories/:id`
- `ChangePasswordSheet` — form stub (backend endpoint not yet confirmed; TODO added)
- `UsageFullSheet` + `UsageFullRow` — full-screen usage breakdown sheet (mirrors Android UsageBottomSheet)

### Why
§25 audit revealed: BMI was invented (not in Android XML), 10+ display rows were missing, 2 Settings sections entirely absent (General + Security), chip display needed for 5 multi-value array fields, Family History was display-only without the relatives sub-field, Plan tab had no "view all" path.

---

## [2026-08-07] Model selector + signup consistency + critical CLAUDE.md rules

### Files changed

| File | Change |
|---|---|
| `Models/ChatModels.swift` | Added `modelType: String?` to `SendMessageRequest` |
| `Features/Richie/ChatService.swift` | `sendMessage` now accepts `model: String = "auto"` and sends `modelType` in request body |
| `Features/Richie/RichieViewModel.swift` | Added `selectedModel`, `showModelPicker`, `allModels`, `selectedModelDisplayName`; `send()` passes `selectedModel` to service |
| `Features/Richie/RichieView.swift` | Added model selector pill (sparkles + name + chevron) above text field in input bar; added `ModelPickerSheet` (medium sheet, thinMaterial, PRO badge for gpt5.3/claude4.5, paywall redirect) |
| `Features/Auth/SignupView.swift` | Restored `pickerField()` to VStack label-above structure with `Color.secondary.opacity(0.1)` background (consistent with `brandedField`); added same background to all three Stepper containers and the DatePicker container |
| `CLAUDE.md` | Added §⚠️ CRITICAL section at top: C1 (grep before removing), C2 (§21 mandatory), C3 (visual consistency), C4 (model selector documented), C5 (sheet glass background) |

### Why
- Model selector was present in Android `fragment_ai.xml` and `AIFragment.java` but never implemented on iOS. Backend confirmed to accept `modelType` in message body.
- Signup form had inconsistent control treatments after previous session: TextFields had `Color.secondary.opacity(0.1)` boxes but Pickers, Steppers, DatePickers had no visual treatment — broke §C3.
- CLAUDE.md lacked explicit rules for grep-before-remove and mandatory §21 research, causing repeated violations.

---

## [2026-08-07] Native iOS input fields + Profile header rebuild

### Files changed

| File | Change |
|---|---|
| `DesignSystem/Theme.swift` | Removed `brandedInputStyle()` extension — it applied `.ultraThinMaterial` + teal stroke to every field, causing Material Design look and backdrop-blur CPU cost |
| `Features/Auth/LoginView.swift` | Grouped Email+Password into a single `VStack(spacing:0)+Divider` container with one `Color.secondary.opacity(0.1)` background; removed per-field material/border |
| `Features/Auth/SignupView.swift` | `brandedField()` now uses `Color.secondary.opacity(0.1)` (plain color, no blur) instead of `.ultraThinMaterial`+stroke; `pickerField()` is now a native label-left/menu-right HStack row; removed `.ultraThinMaterial`+`.overlay` from all DatePicker and Stepper containers |
| `Features/Profile/ProfileView.swift` | Rebuilt `ProfileHeaderView` from Android `fragment_profile.xml`: compact HStack (58pt avatar + name/email/pill + Spacer) instead of tall VStack stack; added "At a Glance" 4-column stats row (Weight, Sleep, Water, BMI) with vertical dividers — mirrors Android's stats section; removed completion gauge from header |

### Why
- Login/Signup fields used `.ultraThinMaterial` on every individual field (up to 10+ blur layers in signup), causing slow rendering and a Material Design outlined-field appearance — not native iOS.
- Profile header was a tall vertical stack (avatar → name → email → location → pills → gauge) with no visual hierarchy match to Android. Android XML shows a compact horizontal header row + a 4-stat "at a glance" row below it.

---

## [2026-08-07] Richie logo fix; ProfileView native List/Section redesign; location permission

### Files changed

| File | Change |
|---|---|
| `richhealth/Features/Richie/RichieView.swift` | Toolbar + empty-state: replaced `Image(systemName: "sparkles")` with `Image("AppLogo")` (26×26 rotating in toolbar, 64×64 in empty state). Matches Android AIFragment logo treatment. |
| `richhealth/Features/Profile/ProfileView.swift` | Full redesign of profile display. Removed custom section-label + GlassCard pattern (`InfoTabView`, `SettingsTabView`, `PlanTabView` structs). Replaced with `List { Section(...) { ProfileInfoRow } }` using `.insetGrouped` style — the native iOS pattern already used in EditProfileSheet. All field parity preserved. Settings section (AI prefs, toggles, logout) and Plan section inline in List body. |

### What changed & why
- **Richie logo**: Was still using `sparkles` SF Symbol. Android AIFragment uses the app logo (`ic_launcher`); the iOS equivalent is `Image("AppLogo")`. Color removed (raster PNG is already teal).
- **Profile design**: Prior implementation built a custom section-label-above-GlassCard system that duplicated what `List { Section }` does natively. Removed `InfoTabView`, `SettingsTabView`, `PlanTabView` structs entirely. Profile display now uses `@ViewBuilder` functions that return `Section` views directly into the main `List`, giving the native iOS settings-app appearance — same pattern as the EditProfileSheet `Form { Section }` that was already correct.
- **Location permission (manual step required)**: `NSLocationWhenInUseUsageDescription` was missing from build settings. Required for AQI `CLLocationUpdate.liveUpdates()`. User needs to add via Xcode target Build Settings (cannot edit `.pbxproj` while Xcode is open).

---

## [2026-08-07] Logging, first-run resilience, Profile UI redesign, process rules in CLAUDE.md

### Files changed

| File | Change |
|---|---|
| `Core/Networking/APIClient.swift` | Added `rhLog()` — `#if DEBUG` print logging on every request (`→`), success (`←`), and error (`✗`). Filter Xcode console with `[RH]`. Covers both JSON and multipart calls. |
| `Features/HealthHub/HealthHubViewModel.swift` | Made all three async loads independent (`try?` per call). First-run empty data no longer shows an error — each count defaults to 0. Added `reload()` method for pull-to-refresh. |
| `Features/Profile/ProfileView.swift` | Redesigned InfoTabView to match Android `fragment_profile.xml` pattern: small uppercase section labels (ABOUT / PHYSICAL / FITNESS & DIET / LIFESTYLE / HABITS / REPRODUCTIVE HEALTH / MEDICAL) above each GlassCard. Redesigned `ProfileInfoRow` to include teal icon (22pt fixed width) → label (secondary) → value (right-aligned), matching Android's icon \| label \| value row format. SettingsTabView now uses same section-label pattern, teal-tinted toggles with Label icons, and section-based GlassCard grouping. |
| `CLAUDE.md` | Added §21 (mandatory 3-agent pre-implementation research), §22 (post-phase UX coherence checklist), §23 (logging + padding rules), §24 (holistic fix rule). Updated §2 Golden Rules. |

### What changed and why

**Logging:** No network visibility during testing made debugging guesswork. `rhLog()` in APIClient is the single source — all 4xx/5xx/transport/decode errors are visible in Xcode console with `[RH]` filter.

**HealthHub first-run error:** `async let (stats, medStats, reports)` combined with `try await` meant ANY failure (e.g., empty data for new user) triggered an error alert. Fixed by making each load independent with `try?` and defaulting counts to 0.

**Profile UI redesign:** Android `fragment_profile.xml` uses section labels (11sp, uppercase, #666666) ABOVE MaterialCardView groups, with rows of icon (20dp, teal) | label | value. iOS was using `Label("About")` headers INSIDE GlassCards with no icons on rows. Now matches Android's visual hierarchy exactly.

**CLAUDE.md process rules:** Codified the pre-implementation 3-agent research requirement, post-phase UX coherence checklist, logging standards, and holistic fix discipline after finding repeated pattern violations.

**Key learnings from Android XML research:**
- Android profile uses SectionLabel (above cards) + MaterialCardView (with rows) — section header is OUTSIDE the card, not inside it
- Android onboarding uses RecyclerView of selectable cards (NOT dropdowns) for: activity, goals, diet, habits, sleep, stress, blood type, conditions — this is pending for iOS signup
- Android signup step 2 collects systolic BP, diastolic BP, resting heart rate — these fields are missing from iOS signup/profile (pending: verify against User.js before adding)

---

## [2026-08-07] Signup + Profile — full field parity with Android OnboardingActivity & User.js schema

### Files changed

| File | Change |
|---|---|
| `Features/Auth/LoginView.swift` | Logo swapped from `cross.case.fill` to `Image("AppLogo")` (ic_launcher.png from Android) |
| `Assets.xcassets/AppLogo.imageset/` | **Created** — 285×285 teal flower PNG copied from Android `ic_launcher.png`; used everywhere the app logo appears |
| `Models/UserProfile.swift` | **Rewritten** — added 20+ fields from User.js mongoose schema: location, waistCircumference, sleepHours, waterIntake, mealsPerDay, stressLevel, screenTimeBeforeBed, sunExposure, occupationType, smokingStatus, alcoholConsumption, caffeineHabit, menstrualStatus, pregnancyStatus, averageCycleLength, averagePeriodLength, contraceptionMethod, menstrualSymptoms, ethnicity. Added computed helpers: `smokingLabel`, `stressLabel`, `screenTimeLabel`, `caffeineLabel`, `menstrualStatusLabel`, `showReproductiveHealth`, `completionPercent`. |
| `Models/AuthModels.swift` | **Rewritten** — `SignupRequest` expanded with optional fields from OnboardingActivity (location, bloodType, sleepHours, smokingStatus, alcoholConsumption, caffeineHabit, medicalConditions, allergies); `UpdateProfileRequest` now covers 35+ fields with full `encodeIfPresent` encoding (no null overwrites in MongoDB $set) |
| `Features/Auth/SignupViewModel.swift` | **Rewritten** — 5 steps total (was 4): account, personal (with location), physical (with blood type), goals, lifestyle & health (sleep, smoking, alcohol, caffeine, conditions, allergies). `totalSteps = 5`. All new fields mapped to `SignupRequest`. |
| `Features/Auth/SignupView.swift` | **Rewritten** — new Step 4 (Lifestyle) with sleep Stepper, smoking/alcohol/caffeine pickerFields, multiline conditions/allergies text fields; step 1 location field; step 2 blood type picker; 5-entry icon/caption arrays. All helpers (`brandedField`, `pickerField`) kept DRY and consistent. |
| `Features/Profile/ProfileViewModel.swift` | **Rewritten** — added edit fields for all 30+ new profile fields: location, ethnicity, waist, sleep, water, meals, stress, screen time, sun, occupation, smoking, alcohol, caffeine, full reproductive health block. `prepareEditForm()` and `saveProfile()` updated to map all fields. |
| `Features/Profile/ProfileView.swift` | **Rewritten** — `InfoTabView` gains: location+ethnicity in About card, waistCircumference in Physical card, new Lifestyle GlassCard (sleep/water/meals/stress/screen/sun/occupation), new Habits GlassCard (smoking/alcohol/caffeine), conditional Reproductive Health GlassCard (Female/Other gender), family history in Medical card. `EditProfileSheet` gains Personal (location, ethnicity), Physical (waist), Lifestyle, Habits, and conditional Reproductive Health Form sections. |

### What changed and why

**Root cause:** Initial Profile and Signup only covered the ~10 required backend fields. User.js mongoose schema has 100+ fields. Android's OnboardingActivity (the primary signup flow, not SignupActivity) collects ~21 steps of optional data. All of this was missing.

**Process followed:** Agent research on OnboardingActivity.java (full 21-step flow), User.js schema (full mongoose model), and authController/userController confirmed exact field names and optional/required status.

**Key decisions:**
- `encodeIfPresent` in `UpdateProfileRequest.encode(to:)` — MongoDB `$set` treats explicit `null` as a write that clears data. Omitting the key is the correct PUT behavior; `encodeIfPresent` achieves this.
- Reproductive health section in EditProfileSheet is conditioned on `editGender == "Female" || editGender == "Other" || !editMenstrualStatus.isEmpty` — mirrors Android's OnboardingActivity which shows those questions based on gender selection.
- `let sunLabel: String` with deferred switch inside `@ViewBuilder` causes "Type '()' cannot conform to 'View'" — fixed with IIFE closure pattern.

---

## [2026-08-07] UI/UX audit + hardcoded-color sweep + Login/Signup card layout

### Files changed

| File | Change |
|---|---|
| `UI_AUDIT.md` | **Created** — Android→iOS layout fidelity audit; records gaps, fixes, and intentional iOS patterns per screen |
| `Features/Auth/LoginView.swift` | Added "Forgot password?" teal link (right-aligned, between password field and login button — matches Android); annotated `.tint(.white)` on ProgressView as `// contrast on teal button` |
| `Features/Auth/SignupView.swift` | Replaced SwiftUI `Form` in multi-step form with `GlassCard` + `brandedInputStyle()` fields, matching Android's `MaterialCardView` + styled-input layout; Steppers and DatePicker wrapped in branded material rows; menu Pickers in branded HStack containers; `brandedField()` and `pickerField()` local helpers for DRY labeled rows |
| `Features/Services/FeedSheetView.swift` | Annotated `.white` in tab chip foreground as `// white: contrast on teal chip` |
| `Features/Services/WorkoutSheetView.swift` | Annotated `.red` error message as `// error feedback` |
| `Features/Services/NutriCheckSheetView.swift` | Annotated `.red` error as `// error feedback`; `.tint(.white)` on button as `// contrast on teal button`; `.red` thumbsdown as `// negative reaction indicator` |
| `Features/Services/DoctorSheetView.swift` | Annotated two `.red` error messages as `// error feedback` |

### What changed and why

**User feedback:** The signup form used SwiftUI's default `Form` which looks like a plain grouped list — very different from Android's dark `MaterialCardView` + `#262626`-bg styled-input layout. LoginView already had the correct GlassCard pattern; Signup was redesigned to match it.

**"Forgot password?" gap:** Android's `activity_login.xml` has a `forgot_password` TextView (teal, right-aligned) that was never ported. Added as a placeholder `Button` with a `// TODO: password reset flow` marker.

**Color annotation sweep:** All hardcoded `.red`, `.white`, `.orange`, `.green` uses across feature code now carry one of: `// error feedback`, `// contrast on teal button/chip`, or `// negative reaction indicator`. Zero `Color(red:green:blue:)` calls outside `Theme.swift`. StatusLevel-routed colors in HealthHub sheets were already correct.

---

## [2026-08-06] Phase 5 — Profile tab (3-tab view, edit profile, pro status, usage rings)

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/UserProfile.swift` | Extended with all profile fields: phoneNumber, dateOfBirth, height, weight, activityLevel, primaryGoal, dietType, bloodType, medicalConditions, allergies, proSubscriptionPlan, proGrantedBy, aiPreferences. Added `AIPreferences` struct with custom `encode(to:)` using `encodeIfPresent` (prevents nil fields overwriting backend data on PUT). Added computed helpers: `completionPercent`, `activityLevelLabel`, `age`, `parseDOB`. Changed `Decodable` → `Codable`. |
| `richhealth/Models/AuthModels.swift` | Added `ProAccess` (GET /api/user/pro-access response with isPro/tier/expiresAt and display helpers). Added `UserUsageResponse` with nested `UsageEntries` and `Entry` structs (GET /api/user/usage response — fraction/displayText computed on Entry). Added `UpdateProfileRequest` with all optional fields + custom `encode(to:)` using `encodeIfPresent` so only non-nil fields are sent to `$set` in MongoDB. Confirmed all paths/shapes against userController.js. |
| `richhealth/Core/Auth/AuthManager.swift` | Added `updateProfile(_:)` → PUT /api/user/profile, refreshes `currentUser`. Added `fetchProAccess()` → GET /api/user/pro-access. Added `fetchUsage()` → GET /api/user/usage. All three confirmed against userController.js. |
| `richhealth/Features/Profile/ProfileViewModel.swift` | Full rewrite. Adds proAccess, usageData state. load() fetches profile (if missing) then runs fetchProAccess + fetchUsage concurrently via async let. prepareEditForm(from:) populates all edit fields including DOB toggle pattern. saveProfile(auth:) builds UpdateProfileRequest from edit state, only sends non-nil/non-empty fields. saveAIPreferences(auth:) sends only aiPreferences sub-object. syncAIPrefs() syncs VM state from currentUser. |
| `richhealth/Features/Profile/ProfileView.swift` | Full rewrite. 3-tab segmented control: Profile \| Settings \| Plan. ProfileHeaderView: initials avatar (72pt brandTeal circle), name, Pro/free tier pill, email-verified pill, completeness Gauge. InfoTabView: 4 GlassCards (About / Physical / Fitness & Diet / Medical — Medical only shown if data present). SettingsTabView (@Bindable vm): AI Preferences card (segmented tone/length pickers, custom instructions text field, 3 toggles, Save button), Account card (notifications placeholder), Logout. PlanTabView: plan card with tier/expiry/status pill + upgrade button (→ PaywallView), usage rings 2-column grid (icon-primary per §18). EditProfileSheet (@Bindable vm): Form sections — Account, Personal (DOB toggle pattern), Physical (number fields), Fitness (pickers), Medical (comma-separated text fields). Uses @Bindable local in body for $vm sheet bindings. |
| `richhealth/Features/Paywall/PaywallView.swift` | Updated from placeholder to proper paywall: crown icon, 6-feature list (GlassCard per feature), Upgrade to Pro button (shows "payment pending" alert — open decision §10). presentationDetents([.medium, .large]) + thinMaterial background + drag indicator. |

### What changed and why

**Pro status from server:** `ProfileViewModel.load()` calls `fetchProAccess()` concurrently with `fetchUsage()`. This is the correct pattern per CLAUDE.md §7 — never derive Pro state locally (Android's `ProStatusManager.isProUser()` had a boolean logic bug). The server is always authoritative.

**encodeIfPresent pattern:** `UpdateProfileRequest` and `AIPreferences` use custom `encode(to:)` with `encodeIfPresent` for all fields. MongoDB's `$set` treats null literally (sets field to null), so we must omit nil fields entirely from the PUT body. A nil field means "don't touch this field on the server," not "clear it."

**DOB toggle pattern:** The edit form uses `editDOBEnabled: Bool` + `editDOB: Date` instead of `Date?`. This avoids `Binding<Date?>` → `Binding<Date>` unwrapping complexity in SwiftUI and makes the UX clear: a toggle explicitly enables/disables the DOB field.

**@Bindable local in body:** `@Bindable var vm = vm` in `ProfileView.body` enables `$vm.showEditSheet` / `$vm.showPaywall` sheet bindings from the `@State`-owned Observable vm. SettingsTabView and EditProfileSheet declare `@Bindable var vm` as a parameter for their own two-way bindings (Picker, Toggle, TextField).

**Edge cases ported (§2A from Android ProfileFragment):**
- Profile completeness ring (mirrors Android `completeness ring` percentage indicator)
- Pro tier display names (Ultra/Family/Plus/Pro/Free — mirrors `planDisplayName` in Android)
- Usage rings with count/limit display (mirrors Android Plan tab usage rings)
- Family-member "granted by" — detected from `proAccess.tier == "family_member"`
- Empty/not-set display throughout Info tab (mirrors Android `orEmpty()` → "—")
- AI preferences with autofillCards excluded from iOS surface (not shown; never overwritten)

---

## [2026-08-06] Android-inspired UI pass — login redesign, AccentColor, HealthRecordRow consistency, SignupView fix

### Files changed

| File | Change |
|---|---|
| `Features/Auth/LoginView.swift` | Full redesign: removed `Form`, added logo section (`cross.case.fill` 56pt icon + "RichHealth" 32pt bold teal + tagline), form inside `GlassCard` with `brandedInputStyle()` fields, 52pt full-width button, `signupCTA` below. Hides nav bar. |
| `DesignSystem/Theme.swift` | `brandTeal` updated to exact Android #008B8B (`red:0, green:139/255, blue:139/255`). Added `brandedInputStyle()` View extension: `.ultraThinMaterial` background + teal 45% stroke overlay on TextFields. |
| `Assets.xcassets/AccentColor.colorset/Contents.json` | Updated green/blue from 0.600/0.550 → 0.545/0.545 to match exact Android teal RGB. |
| `Features/Auth/SignupView.swift` | Replaced `ProgressView` with 4-segment `stepBars` (Capsule, teal=done/current, gray=upcoming). Added `stepHeaderIcon` (64pt teal circle + SF Symbol + caption per step). **Build error fixed:** both computed properties were accidentally placed outside the struct; moved inside `SignupView` — struct now closes at line 265. |
| `Features/HealthHub/HealthHubView.swift` | Added `SectionLabel` (uppercase, 11pt bold, `.secondary`, kerning 1.0 — mirrors Android section headers). Sections: DAILY TRACKING + HEALTH RECORDS. `HubCard` redesigned: 48×48 teal icon container (12% opacity), teal title, chevron. |
| `DesignSystem/Components/HealthRecordRow.swift` | **NEW canonical row** for all Health Hub list views. Parameters: `icon, title, subtitle?, pillText?, pillLevel?, date?`. 44×44 teal icon container + headline/subheadline VStack + trailing pill+date. Replaces 4 bespoke row structs. |
| `Features/HealthHub/SymptomsSheetView.swift` | Removed `SymptomRow`, uses `HealthRecordRow`. |
| `Features/HealthHub/MeasurementsSheetView.swift` | Removed `MeasurementRow`, uses `HealthRecordRow`. |
| `Features/HealthHub/MedicationsSheetView.swift` | Removed `MedicationRow`, uses `HealthRecordRow`. |
| `Features/HealthHub/PeriodLogSheetView.swift` | Removed `PeriodLogRow`, uses `HealthRecordRow`. |
| `Features/HealthHub/MedicalReportsSheetView.swift` | Kept `ReportRow` (polling-state complexity differs), but aligned icon container to 44×44 teal + `Theme.Spacing.m` horizontal gap to match `HealthRecordRow` visually. |

### What changed and why

**Android design guideline pass:** User requested iOS UI adopt Android design cues as a visual guideline (not a copy). Research agents read Android XML layouts for LoginActivity, HealthHub panels. Key takeaways applied: logo above the form (not inside nav title), teal (#008B8B) as primary accent everywhere, section headers in uppercase small caps, icon containers for each list row type.

**HealthRecordRow:** All five Health Hub sheets had different row layouts for structurally identical data (icon + title + subtitle + status pill + date). Extracted into one canonical component so changes propagate everywhere. Apple's native pattern: leading icon container, primary+secondary text VStack, trailing metadata — clean, consistent, accessible.

**SignupView build fix:** After adding `stepBars` and `stepHeaderIcon` in the prior session, the edit landed both properties outside the `SignupView` struct (after its closing `}`). Compiler error "Extraneous '}' at top level" at line 266. Fixed by removing the premature closing brace so both properties are inside the struct.

---

## [2026-08-06] Fix Health Hub API paths, revert SwipeHintModifier, update CLAUDE.md process rules

### Files changed

| File | Change |
|---|---|
| `Features/HealthHub/HealthDataService.swift` | **Bug fix:** all endpoint paths corrected from `/api/health/data*` → `/api/medical-data*`. Root cause: paths were not verified against `../richhealthbackend/routes/medicalDataRoutes.js`. This caused "Unexpected Server Response" (JSON decode failure on 404 HTML). |
| `Features/HealthHub/SymptomsSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/HealthHub/MeasurementsSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/HealthHub/MedicationsSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/HealthHub/MedicalReportsSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/HealthHub/PeriodLogSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/Services/NutriCheckSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/Services/WorkoutSheetView.swift` | Removed `.swipeHint()` from List row |
| `Features/Richie/RichieView.swift` | Removed `.swipeHint()` from ChatHistorySheet List row |
| `CLAUDE.md` | Added §19 (swipe hint intentionally deferred — why `.offset(x:)` on List rows breaks scroll, what clean alternatives to consider) and §20 (rule: always read Android XML + Java + backend controller before implementing any feature) |

### What changed and why

**Health Hub API path fix:** `HealthDataService.swift` was calling `/api/health/data/` but the backend mounts the route at `/api/medical-data/`. The server returned a 404 HTML page, which the `JSONDecoder` could not parse, throwing `APIError.decoding` → "Unexpected Server Response." Fixed by reading `medicalDataRoutes.js` directly. §20 added to CLAUDE.md to enforce this process going forward.

**SwipeHintModifier reverted:** `.swipeHint()` used `.offset(x:)` to briefly slide list rows left. This conflicted with UITableView's built-in gesture recogniser system inside SwiftUI List, causing scroll jitter and lost momentum. All 8 usages removed. `SwipeHintModifier.swift` stays in the codebase but must not be applied to List rows without replacing the offset-based approach. §19 in CLAUDE.md documents the deferred status and cleaner alternatives (one-time header banner, `.badge()`, or no hint).

**Android home cards clarified:** Research confirmed Android's HomeFragment uses card-to-detail navigation (MaterialCardView + startActivity), NOT expandable accordions. The iOS sheet pattern is already the correct equivalent — no accordion to port.

---

## [2026-08-06] Holistic UX — session cache, Richie logo, full-width suggestions, card consistency

### Files changed

| File | Change |
|---|---|
| `Core/Cache/SessionCache.swift` | NEW — TTL UserDefaults cache utility with `save/load/loadToday/clearAll`. Codable envelope with savedAt timestamp. All keys prefixed `rh.cache.*` to avoid collisions. |
| `Models/ServicesModels.swift` | `BriefingResponse`, `BriefingCard`, `DailyDigestResponse`, `DietaryInsightsResponse`, `UsageStatus`, `AQIData` changed from `Decodable` → `Codable` to support caching |
| `Features/Services/ServicesHomeViewModel.swift` | Briefing + digest: stale-while-revalidate with same-day TTL. Dietary: 8h TTL. AQI: 1h TTL — **skips location entirely on cache hit**, avoiding the expensive `CLLocationUpdate.liveUpdates()` flow. `reload()` calls `SessionCache.clearAll()` so pull-to-refresh always fetches fresh data. |
| `Features/Richie/RichieView.swift` | Logo: replaced `navigationTitle` with `.principal` ToolbarItem showing `[sparkles icon] Richie`. Sparkles icon rotates continuously at 6 s/rev idle; accelerates to 1.5 s/rev while `vm.isSending` (mirrors Android AIFragment ObjectAnimator). Suggestions: replaced 2-column LazyVGrid with full-width VStack rows — each row shows question + why text + trailing teal send arrow. |
| `Features/Services/ServicesHomeView.swift` | `DigestCardView`: added expand/collapse toggle ("Read more" / "Show less") for long advisory text; collapsed to 3 lines. `AQICardView`: added `minHeight: 88` to prevent layout jump between states. `WorkoutsCardView`: replaced `ContentUnavailableView` with inline `HStack` empty state (keeps card height consistent). `FeedPreviewRowView`: category label `→ .uppercased() + .semibold + Theme.brandTeal`. |
| `CLAUDE.md` | Added §16 (session cache policy), §17 (brand teal usage rules), §18 (layout density + card consistency rules) |

### What changed and why

**Session caching:** Services data was re-fetched on every app open — including the location + geocode + AQI API chain which requires system permission and network calls. Now: briefing/digest show in <100ms from UserDefaults if already fetched today; AQI skips location entirely for 1 hour after a successful fetch. Pull-to-refresh busts all caches for truly fresh data.

**Richie logo animation:** Android's AIFragment shows the app icon spinning in the empty state (2 s/rev) and speeds up when the AI is thinking. The iOS version uses `.principal` toolbar placement so the rotating sparkle sits directly beside the "Richie" text — cleaner than a large centered icon, and always visible even when the message list is populated. Speed transition (idle ↔ thinking) is driven by `vm.isSending`.

**Full-width suggestions:** The 2-column suggestion grid was cramped on iPhone — text wrapped after ~3 words per column and tapping the right card was error-prone. Full-width rows give each suggestion 80%+ more horizontal space and add a visible teal send arrow that makes the tap action obvious.

**Card height consistency:** `ContentUnavailableView` inside a GlassCard causes 5× height variation between empty and populated states. Replaced with inline HStack empty states. AQI card got a `minHeight` to stop the card from jumping from a single line to a large number + chart. Digest text is now truncated to 3 lines with an expand toggle to keep the card predictable.

**Brand teal for categories:** Feed item categories were `.tertiary` (barely visible). Changed to `Theme.brandTeal + .uppercased() + .semibold` — consistent with the brand accent rule and makes content type scannable at a glance.

---

## [2026-08-06] UX polish — swipe hints, keyboard dismissal, title fixes, AccentColor

### Files changed

| File | Change |
|---|---|
| `DesignSystem/Components/SwipeHintModifier.swift` | NEW — one-time slide animation teaching swipe affordance; `@AppStorage` keyed per list so it fires once across app launches |
| `Assets.xcassets/AccentColor.colorset/Contents.json` | Set to brand teal (#008B8B equivalent in sRGB) — all system controls (toggles, sliders, links) now use teal tint automatically |
| `App/RootView.swift` | Tab label "User" → "Profile" |
| `Features/Profile/ProfileView.swift` | `navigationTitle` "User" → "Profile"; button "Edit profile" → "Edit Profile"; sheet title "Edit profile" → "Edit Profile" |
| `Features/Richie/RichieView.swift` | Added `.scrollDismissesKeyboard(.interactively)` to both `emptyChatView` and `messageListView` ScrollViews; added `.presentationBackground(.thinMaterial)` to `ChatHistorySheet`; added `.swipeHint(key: "chatHistory")` on sessions list |
| `Features/HealthHub/SymptomsSheetView.swift` | Search prompt simplified to "Search symptoms"; `.swipeHint(key: "symptoms")` on list |
| `Features/HealthHub/MeasurementsSheetView.swift` | Search prompt → "Search measurements"; `.swipeHint(key: "measurements")` |
| `Features/HealthHub/MedicationsSheetView.swift` | Search prompt → "Search medications"; swipe action "Stop" → "Discontinue" (matches confirmation dialog); `.swipeHint(key: "medications")` |
| `Features/HealthHub/MedicalReportsSheetView.swift` | Search prompt → "Search reports"; "Analyse Report" → "Analyze Report" (US English); `.swipeHint(key: "reports")` |
| `Features/HealthHub/PeriodLogSheetView.swift` | Search prompt → "Search logs"; `.swipeHint(key: "periodLogs")` |
| `Features/Services/NutriCheckSheetView.swift` | "Analysing…" → "Analyzing…"; `.swipeHint(key: "nutriHistory")` on history list |
| `Features/Services/WorkoutSheetView.swift` | `.swipeHint(key: "workouts")` on workout list |
| `Features/Services/ServicesHomeView.swift` | "analyse" → "analyze" in NutriCheck description |

### What changed
- **Keyboard dismissal**: scrolling up in the Richie chat view now pulls down the keyboard interactively (both the empty state and the message list), matching standard iOS messaging apps.
- **Swipe affordance hints**: the first row of every list with swipe actions briefly slides left ~42 pt on first visit then springs back. Keyed to `AppStorage` per list so it plays once ever, not on every open.
- **AccentColor wired**: system controls throughout the app now use brand teal as the accent automatically — no per-control `.tint()` needed.
- **Title consistency**: "User" tab → "Profile" everywhere; "Edit profile" → "Edit Profile" (title case); "Stop" medication action → "Discontinue" (matches the confirmation dialog that already said "Discontinue medication?"); "Analyse"/"Analysing" → "Analyze"/"Analyzing" (US English throughout).
- **ChatHistorySheet** was missing `.presentationBackground(.thinMaterial)` — now matches all other sheets.
- **Search prompts**: removed the item-count interpolation ("Search 3 symptom(s)") — simpler, locale-safe, standard iOS.

---

## [2026-08-06] Design system sweep — tokens, consistency, Phase 1–4 audit

### Files changed

| File | Change |
|---|---|
| `DESIGN_SYSTEM.md` | NEW — comprehensive design reference: philosophy, color tokens, typography, spacing, corner radii, icon sizing, component catalog, layout patterns, Android→iOS mapping, anti-patterns, verification checklist |
| `DesignSystem/Theme.swift` | Added `Spacing.xs=4`, `Spacing.xl=32`; added `CornerRadius` enum (card=20, sheet=22, button=12, icon=14, input=12); added `IconSize` enum (touch=44, avatar=44, card=30, inline=20) |
| `DesignSystem/Components/GlassCard.swift` | `cornerRadius: 20` → `Theme.CornerRadius.card` |
| `Features/Auth/LoginView.swift` | `.padding(.trailing, 4)` → `Theme.Spacing.xs`; `.foregroundStyle(.red)` annotated with `// error feedback` |
| `Features/Auth/SignupView.swift` | Two `.padding(.trailing, 4)` → `Theme.Spacing.xs`; two error `.red` annotated |
| `Features/Richie/RichieView.swift` | All `cornerRadius: 12/18/20` → `Theme.CornerRadius.*`; `spacing: 4/5/6` → `Theme.Spacing.xs`; `spacing: 8/10` → `Theme.Spacing.s`; `.padding(.vertical, 10)` → `.padding(.vertical, Theme.Spacing.s)`; `.padding(.horizontal, 14)` → `Theme.Spacing.m`; `.foregroundStyle(.white)` annotated `// contrast`; `.font(.system(size: 32))` → `.font(.largeTitle)` |
| `Features/HealthHub/HealthHubView.swift` | `spacing: 4` in StatChip → `Theme.Spacing.xs` |
| `Features/HealthHub/SymptomsSheetView.swift` | Added `.presentationDetents`, `.presentationDragIndicator`, `.presentationBackground(.thinMaterial)` to main body + nested form sheets; `spacing: 4` rows → `Theme.Spacing.xs` |
| `Features/HealthHub/MeasurementsSheetView.swift` | Same presentation modifier fixes + spacing |
| `Features/HealthHub/MedicationsSheetView.swift` | Same + `.tint(.orange)` → `.tint(StatusLevel.orange.color)` on Stop action |
| `Features/HealthHub/PeriodLogSheetView.swift` | Same presentation modifiers + `spacing: 6` → `Theme.Spacing.xs` |
| `Features/HealthHub/MedicalReportsSheetView.swift` | Same + `.foregroundStyle(.orange)` → `StatusLevel.orange.color`; `spacing: 4/6/8` → `Theme.Spacing.xs/xs/s` |
| `Features/HealthHub/FamilySheetView.swift` | Same presentation modifiers + `spacing: 4` → `Theme.Spacing.xs` |
| `Features/Services/ServicesHomeView.swift` | `.padding(.horizontal, 4)` → `Theme.Spacing.xs`; `spacing: 4/6` → `Theme.Spacing.xs`; `cornerRadius: 10` on thumbnail → `Theme.CornerRadius.icon` |
| `Features/Services/NutriCheckSheetView.swift` | `cornerRadius: 10` → `Theme.CornerRadius.icon`; `.foregroundStyle(.orange)` → `StatusLevel.orange.color`; `spacing: 12` → `Theme.Spacing.s` |
| `Features/Services/WorkoutSheetView.swift` | `spacing: 4/6` → `Theme.Spacing.xs` |
| `Features/Services/DoctorSheetView.swift` | `cornerRadius: 12` → `Theme.CornerRadius.button`; `frame(44, 44)` → `Theme.IconSize.avatar`; `spacing: 4/8/12` → `Theme.Spacing.xs/s/s` |
| `Features/Services/FeedSheetView.swift` | `cornerRadius: 12` → `Theme.CornerRadius.button`; `spacing: 4/6/8` → `Theme.Spacing.xs/xs/s` |

### What changed

**Design tokens extended:** Theme.swift now has a complete spacing scale (xs→xl), corner radius constants for every surface type, and icon size constants. GlassCard uses `Theme.CornerRadius.card` instead of a magic number.

**Presentation consistency (Phase 3):** All 6 Health Hub sheet views were missing `.presentationBackground(.thinMaterial)` — they would have rendered with the system default (opaque) instead of the frosted glass look. Added to all main sheet bodies and all nested form sheets.

**Status colors (Phase 3 & 4):** `.tint(.orange)` and `.foregroundStyle(.orange)` replaced with `StatusLevel.orange.color` in Medications stop action, Medical Reports warning icon, and NutriCheck stale-data warning — all route through the canonical 4-state StatusLevel system.

**Spacing sweep (all phases):** All raw `4/6` → `Theme.Spacing.xs`, `8/10` → `Theme.Spacing.s`, `14` → `Theme.Spacing.m`. Micro-spacing of `2pt` between text lines left intentionally (not a layout token).

**Corner radii sweep (Phase 2 & 4):** Raw `12/18/20` → `Theme.CornerRadius.button/card/card` throughout RichieView, Services sheets, and thumbnail clips.

### Why

Android reference design uses: card=18dp, screen-margin=16dp, teal accent `#008B8B`, pure-black background with 5% opaque white surfaces. iOS equivalent: `GlassCard` (`.ultraThinMaterial` + 20pt radius), `Theme.brandTeal`, semantic adaptive colors. The sweep makes every screen consistent with this vocabulary — one token per concept, used everywhere.

`DESIGN_SYSTEM.md` is the permanent reference for all future feature work.

---

## [2026-08-06] Phase 4 — Services/Home tab (briefing, AQI, dietary, feed, workouts, doctor)

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/ServicesModels.swift` | NEW — all Phase 4 Codable DTOs: `UsageStatus`, `BriefingCard`, `DailyDigestResponse`, `DietaryInsightsResponse/Entry`, `NutriCheckRequest/Response/Entry`, `FeedResponse/FeedItem`, `AQIData/Responses/StoreRequest`, `WorkoutRecord/ExerciseRecord/CreateRequest`, `DoctorSearchResult/PendingRecord/IncomingDoctorRequest`. Includes `FeedItem.placeholder` extension for skeleton loading |
| `richhealth/Features/Services/InsightsService.swift` | NEW — wraps `/api/insights/briefing`, `/api/insights/daily-digest`, `/api/insights/dietary-insights`, `/api/insights/nutri-check`. Confirmed against `../richhealthbackend/routes/homeScreenRoutes.js` |
| `richhealth/Features/Services/FeedService.swift` | NEW — wraps `GET /api/feed` (paginated, optional type filter) and `GET /api/feed/:id`. Confirmed against `../richhealthbackend/routes/feedRoutes.js` |
| `richhealth/Features/Services/AQIService.swift` | NEW — wraps `/api/aqi/latest`, `/api/aqi/history`, `/api/aqi/store`. `reverseGeocode()` uses `MKReverseGeocodingRequest` + `addressRepresentations.cityName` (iOS 26 — `CLGeocoder` and `MKMapItem.placemark` both deprecated). Confirmed against `../richhealthbackend/routes/aqiRoutes.js` |
| `richhealth/Features/Services/WorkoutService.swift` | NEW — full CRUD for `/api/fitness/workouts`. Exercise catalogue (`/api/fitness/exercises`) is a backend stub — not called at launch. Confirmed against `../richhealthbackend/routes/workoutRoutes.js` |
| `richhealth/Features/Services/DoctorService.swift` | NEW — all paths use `/api/users/doctor/doctor/*` (double "doctor" — confirmed intentional from backend route mounting). Covers search, connect, pending, incoming requests, cancel, respond. Confirmed against `../richhealthbackend/routes/doctorRoutes.js` |
| `richhealth/Features/Services/ServicesHomeViewModel.swift` | Rewrite — `withTaskGroup` loads 6 data sources concurrently (briefing, digest, dietary, feed, workouts, doctors). Separate `loadAQI()` uses `CLLocationUpdate.liveUpdates()` (iOS 17 async CoreLocation, no explicit auth call needed). `AQILoadStatus` enum tracks location→geocode→fetch progression. `ServicesSheet` enum drives one `.sheet(item:)` for all four drawer sheets |
| `richhealth/Features/Services/ServicesHomeView.swift` | Rewrite — 7-card scroll dashboard: briefing horizontal strip (skeleton), daily advisory, AQI (mini Swift Charts trend line), dietary insights + NutriCheck CTA, feed preview (3 items), workouts preview (3 items), doctor inline-accept section. `.foregroundStyle(.green/.orange)` replaced with `StatusLevel.*.color` per §14 |
| `richhealth/Features/Services/NutriCheckSheetView.swift` | NEW — Check tab: food input + result card (statusLevel pill + reason). History tab: past checks with swipe-delete, stale-data banner (`dataChangesSince`), thumbs up/down reaction. 429 → `PaywallView` sheet |
| `richhealth/Features/Services/WorkoutSheetView.swift` | NEW — workout list (swipe-delete), create sheet. Exercise catalogue stub shown as note (library coming soon). Weight == 0 displayed as "Bodyweight" |
| `richhealth/Features/Services/DoctorSheetView.swift` | NEW — three-tab segmented (Search / Connected / Requests). Search by name/specialty/licence. Connected list. Outbound pending + incoming request rows with Accept/Decline inline. `connectionStatus` drives StatusPill level |
| `richhealth/Features/Services/FeedSheetView.swift` | NEW — full paginated feed. Type filter chips (All/Articles/News/Podcasts). Last-item `.onAppear` triggers `loadMore()`. `AsyncImage` thumbnail, Pro pill. `ContentUnavailableView` on empty |
| `richhealth.xcodeproj/project.pbxproj` | Added `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` to Debug + Release build settings (required for CoreLocation; added via Xcode Build Settings UI — not direct pbxproj edit) |

### What changed

**Models:** `ServicesModels.swift` covers all Phase 4 server contracts. `AQIData.statusLevel` maps AQI US index ranges to the four `StatusLevel` levels (§12). `NutriCheckEntry.statusLevel` and `.recommendationLabel` map the five recommendation strings. `DoctorSearchResult.connectionStatusLevel` maps connection status to StatusLevel. `FeedItem` uses `_id` → `id` CodingKeys.

**Services:** Five new service structs (one per backend route group). All confirm paths from `../richhealthbackend/routes/`. Notable: doctor paths have `/doctor/doctor/` (intentional double — backend mounts doctor-user routes under `/api/users/doctor/doctor`). AQI `reverseGeocode` uses iOS 26 `MKReverseGeocodingRequest` + `MKAddressRepresentations` — `CLGeocoder` and `MKMapItem.placemark` are both deprecated in iOS 26.

**ViewModel:** `load()` uses `withTaskGroup` for maximum concurrency (6 tasks). `loadAQI()` is separate because it depends on device location (slower, different failure modes). `AQILoadStatus` enum (.idle → .requesting → .loaded / .denied / .noData) drives progressive card reveal. After successful geocode, stores AQI reading via `storeAQI` for backend aggregation.

**Dashboard view:** Single `ServicesHomeView` with 7 section cards, all reusing `GlassCard`, `StatusPill`, `.skeleton(isActive:)`, and `Theme.*` tokens per §14. The AQI card shows a mini Swift Charts `LineMark` trend when ≥2 history points are available. No inline `.red`/`.green`/`.orange` literals — all via `StatusLevel.*.color`.

**Four sheet views:** Each is a self-contained `NavigationStack` with `.large` detent + `.thinMaterial` background. NutriCheck has tabbed UX (Check + History) with stale-data warning (ports Android's "data may not be current" pattern from §2A). Doctor sheet uses segmented control (not tabs) as the selection is among 3 closely-related views. Feed sheet uses horizontal filter chips + pagination. Workout sheet notes exercise library stub rather than hiding the feature.

**Edge cases ported (§2A):**
- NutriCheck: 429 → paywall, stale-data warning, thumbs reaction
- AQI: location denied state, no-data state, requesting state with ProgressView
- Feed: empty per-type state, pagination end, Pro-only badge
- Doctor: connection status pill, pending/incoming split, no-connections empty state
- Workouts: empty state, exercise stub note, bodyweight display (weight == 0)

### Why

Phase 4 completes the Services/Home tab. All Android `HomeFragment` cards are rebuilt as native SwiftUI cards. Side-panel pattern from Android is replaced with `.sheet` drawers. Concurrent `withTaskGroup` loading avoids serial API calls that blocked Android's fragment resume. CoreLocation uses the iOS 17+ async `CLLocationUpdate.liveUpdates()` to avoid the deprecated `CLLocationManager` delegate pattern.

Backend paths confirmed from `../richhealthbackend/routes/` and `index.js`. NutriCheck and dietary insights use `/api/insights/*` (not `/api/home/*` as Android sometimes used).

---

## [2026-08-06] Phase 3 — Health Hub tab (six panels, services, models)

### Files changed

| File | Change |
|---|---|
| `richhealth/Core/Networking/Endpoint.swift` | Added `.patch = "PATCH"` to `HTTPMethod` enum (needed for medication discontinue, sharing toggles) |
| `richhealth/Core/Networking/APIClient.swift` | Added `sendMultipart(path:fields:fileData:fileName:mimeType:as:)` for medical report file uploads (multipart/form-data, field name "file" per backend contract) |
| `richhealth/Models/UserProfile.swift` | Added `gender: String?` field — used to gate the Period Log panel (only shown for female-identified users, per Android HealthDataFragment behaviour) |
| `richhealth/Models/HealthDataModels.swift` | NEW — all Phase 3 Codable DTOs: `MedicalDataRecord`, `MedicalDataStats`, `MedicationRecord`, `PeriodLogRecord`, `MedicalReportRecord`, `KeyFinding`, `PossibleCondition`, `RelationshipRecord`, `DependentRecord`, and all request/response wrappers. Also contains shared `MedicalDataRecord.placeholder` and `String.shortDate` extension |
| `richhealth/Features/HealthHub/HealthDataService.swift` | NEW — wraps `/api/health/data` (unified symptoms + measurements). Confirmed against `../richhealthbackend/routes/medicalDataRoutes.js` |
| `richhealth/Features/HealthHub/MedicationService.swift` | NEW — wraps `/api/health/medications` incl. `discontinue()` (PATCH). Confirmed against `../richhealthbackend/routes/medicationRoutes.js` |
| `richhealth/Features/HealthHub/PeriodLogService.swift` | NEW — wraps `/api/health/period-logs`. Confirmed against `../richhealthbackend/routes/periodLogRoutes.js` |
| `richhealth/Features/HealthHub/MedicalReportService.swift` | NEW — wraps `/api/health/reports`. Includes `upload()` (multipart), `requestAnalysis()` (pro-gated), and `pollUntilComplete()` (4 s × 25 attempts). Confirmed against `../richhealthbackend/routes/medicalReportRoutes.js` |
| `richhealth/Features/HealthHub/HealthHubViewModel.swift` | Rewritten — loads stats concurrently (`async let`) from health data stats, medication stats, reports list |
| `richhealth/Features/HealthHub/HealthHubView.swift` | Rewritten — proper dashboard: 3-stat chip row + 6 HubCard entries (period log card gated on `gender == "Female"`). Each card opens its sheet. Gender read from `appEnv.auth.currentUser` |
| `richhealth/Features/HealthHub/SymptomsSheetView.swift` | NEW — list with severity StatusPill (yellow/orange/red 1-10), client-side search, swipe-delete, add/edit form sheet with severity Slider (1-10) + date picker |
| `richhealth/Features/HealthHub/MeasurementsSheetView.swift` | NEW — list with client-computed status StatusPill (per metric type + value), type-dependent unit picker, add/edit form |
| `richhealth/Features/HealthHub/MedicationsSheetView.swift` | NEW — list with ACTIVE (green) / Completed (yellow) StatusPill, discontinue swipe action (confirmation dialog → PATCH), full add/edit form: frequency picker, type picker, administration method picker, "still taking" toggle |
| `richhealth/Features/HealthHub/PeriodLogSheetView.swift` | NEW — list with flow StatusPill, pain label; add/edit form with flow picker and pain Slider (1-5). Only surfaced for female users |
| `richhealth/Features/HealthHub/MedicalReportsSheetView.swift` | NEW — file upload via `.fileImporter` + report type `.confirmationDialog`, analysis polling (Task.sleep 4 s × 25), full analysis detail sheet (key findings, risk/urgency pills, conditions, recommendations). 403 + 429 → paywall |
| `richhealth/Features/HealthHub/FamilySheetView.swift` | NEW — shows relationships (accepted=green, pending=yellow) + dependents section. Add connection form (email + relationship picker). Pro plan "Add to Pro" actions deliberately omitted (blocked by open decision §10 — payment method) |

### What changed

**Networking layer:** `HTTPMethod.patch` added. `APIClient.sendMultipart` builds a multipart/form-data body, injects Bearer token, and maps status codes identically to the regular `send` method.

**Models:** `HealthDataModels.swift` contains all Phase 3 DTOs matched exactly to the backend JSON shapes. The unified `MedicalDataRecord` uses `type: "symptom" | "measurement"` — same as `/api/health/data` — so one struct covers both panels. `MedicalReportRecord.isAnalysisProcessing` and `isAnalysisTrustworthy` are computed properties. Shared `String.shortDate` and `MedicalDataRecord.placeholder` are defined once here to avoid redeclaration across files.

**Dashboard:** `HealthHubView` shows a stats row (symptom/measurement/active-med counts) and one `HubCard` per panel. Period Log card conditionally shown based on user's gender from `AppEnvironment`. Stats loaded concurrently via `async let`.

**Six panels (each: lazy load on `.task`, skeleton on load, `ContentUnavailableView` on empty, swipe-delete, pull-to-refresh, add/edit as nested sheet):**
- **Symptoms:** severity mapped 1-10 → 5 labels (Very Mild…Very Severe), color-coded by StatusLevel
- **Measurements:** client-side status classification per metric type (Blood Pressure, Glucose, Heart Rate, O2, Temperature, Weight, etc.)
- **Medications:** ACTIVE/Completed pill; discontinue shows `.confirmationDialog` before PATCH; "still taking" toggle gates end date field
- **Period Log:** flow intensity (light→green, medium→yellow, heavy→orange); pain level 1-5 with labels
- **Medical Reports:** `.fileImporter` → report type dialog → multipart upload; polling ProgressView during analysis; analysis detail sheet with key findings table, risk/urgency pills, conditions, recommendations. `canAnalyzeThisReport` drives the Analyse CTA; 403/429 route to paywall flag
- **Family:** peer connections with status pills; dependents in a separate section (read-only per Android). Pro plan management omitted pending payment decision

### Why

Phase 3 completes the Health Hub tab. All six Android side panels are rebuilt as native `.sheet` drawers with `.large` detent. Edge cases ported per CLAUDE.md §2A: analysis polling timeout, untrustworthy analysis banner, pro-gated analysis (403 → paywall), limit-reached on upload (429 → paywall), gender-gated period log, discontinue confirmation flow, client-side measurement status classification. No local DB — stateless client per §1.3.

Backend paths confirmed from `../richhealthbackend/routes/` and `index.js` mounting. All canonical paths use `/api/health/*` prefix (not the `/api/medical-data` Android aliases).

---

> Mirror of `../richhealth_android/AI_CHANGE_LOG.md` discipline.
> Format: `## [YYYY-MM-DD] <summary>` → files → what → why.

---

## [2026-08-06] Phase 2 — Richie AI chat (sessions, markdown, limits, history)

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/ChatModels.swift` | Full rewrite: proper server DTOs (`ChatSessionDTO`, `ChatMessageDTO`, `SendMessageResponse`, `ChatSuggestionsResponse`); local `ChatMessage` with `.user/.ai/.log` kind; `SendMessageRequest` body with sessionId removed (now a path param — was the bug noted in the Phase 2 brief) |
| `richhealth/Features/Richie/ChatService.swift` | New: typed service wrapping all 7 chat API paths (createSession, getSessions, getMessages, sendMessage, deleteSession, getSuggestions, toggleSaved) |
| `richhealth/Features/Richie/RichieViewModel.swift` | Full rewrite: session lifecycle (create on first send, load history on demand); optimistic user message with server-side replace; full error routing (429/403 → paywall, 400 monthly-limit → paywall, 400 session-limit → in-chat banner + new chat CTA, network/other → restore input for retry); `ChatLimitKind` enum; suggestions/nudge loading |
| `richhealth/Features/Richie/RichieView.swift` | Full rewrite: empty state with LLM-generated suggestion cards + data nudge; `ChatBubbleView` (user bubble, AI bubble with markdown, log entry); `TypingIndicatorView` (animated dots); `ChatHistorySheet` (session list, swipe-delete, StatusPill "Full" for limit-reached sessions); session limit banner; save/unsave via context menu; `DisclosureGroup` for thinking trace; memory-saved indicator |

### What changed

**ChatModels.swift** — API contract fix: `SendMessageRequest` no longer has `sessionId`; it is a URL path parameter (`POST /api/chat/sessions/:sessionId/messages`). `ChatSessionDTO.id` maps from `"sessionId"` (the UUID used in paths), not `"_id"` (MongoDB ObjectId). `ChatMessageDTO.id` maps from `"_id"` (used for toggleSaved). All `timestamp` fields are `String?` (ISO 8601) to avoid JSONDecoder date-strategy dependency.

**ChatService.swift** — Thin wrapper around APIClient. No business logic. All 7 paths confirmed against `../richhealthbackend/routes/chatRoutes.js` and `../richhealthbackend/controllers/rhChatController.js`.

**RichieViewModel.swift** — Edge-case parity vs Android AIFragment:
- Monthly session limit (400 `"Monthly session limit reached"`) → `showPaywall = true`
- Per-session message limit (400 `"Session limit reached..."` or `isLimitReached: true` in response) → `limitKind = .sessionMessageLimit` → in-chat banner with "Start New Chat"
- Rate limit 429 / 403 notAllowed → `showPaywall = true`
- Network error → input restored so user can retry without losing message
- Opened history session marked `limitKind = .sessionMessageLimit` immediately if `session.isLimitReached == true`
- `toggleSaved` does optimistic toggle with silent server-side revert on failure

**RichieView.swift** — Native iOS patterns (NATIVE_COMPONENTS.md §2, §3):
- History panel (Android side panel) → `.sheet` with `.medium/.large` detents + drag indicator
- Suggestions in `LazyVGrid` — tap fires send immediately (tap-to-ask UX)
- Markdown via `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`
- Thinking trace shown in `DisclosureGroup` (hidden by default) when `reasoning` is non-empty
- Memory-saved indicator uses `brain.head.profile` SF Symbol (subtle `.tertiary` color)

### Why

Phase 2 completes Richie — the primary feature and default tab. Backend is session-based (confirmed in `rhChatController.js`); the iOS client creates sessions lazily on first message and caches them in memory for the app session. All edge cases from the Android `AIFragment` are ported by intent (limit dialogs, per-session vs monthly limits, error recovery) using native iOS patterns per CLAUDE.md §2A.

---

## [2026-08-06] StatusPill 4-state system + CLAUDE.md continuation docs

### Files changed

| File | Change |
|---|---|
| `richhealth/DesignSystem/Components/StatusPill.swift` | Added `StatusLevel` enum (`.green/.yellow/.orange/.red`); `StatusPill` now accepts optional `level:` param; non-status labels still use `tint:` (brand teal default) |
| `CLAUDE.md` | Added §12 (Status Pill canonical 4-state rules + usage table) and §13 (ready-to-paste continuation prompt for next sessions) |

### What changed

- `StatusLevel` enum with 4 cases maps to SwiftUI semantic colours (`.green`, `.yellow`, `.orange`, `.red`) that adapt to light/dark mode.
- `StatusPill(text: "Normal", level: .green)` — status use.
- `StatusPill(text: "Pro")` — non-status label, still uses brand teal (backward compatible).
- CLAUDE.md §12 locks the four states as the only allowed colours for any status signal in the app and documents which state maps to which health/system meaning.
- CLAUDE.md §13 provides a paste-ready prompt so any new chat session can pick up Phase 2 without re-reading all files from scratch.

---

## [2026-08-06] Phase 1 — Auth + shell wired end-to-end

### Files changed

| File | Change |
|---|---|
| `richhealth/Models/AuthModels.swift` | Added `SignupRequest`, `ProfileResponse`, OTP request/response models |
| `richhealth/Models/UserProfile.swift` | Added `emailVerified: Bool?` field |
| `richhealth/Core/Networking/APIError.swift` | Added `userMessage` extension for user-facing error strings |
| `richhealth/App/AppEnvironment.swift` | Embedded `AuthManager`; added computed `phase` from `auth.isAuthenticated`; added `bootstrap()` |
| `richhealth/Core/Auth/AuthManager.swift` | Implemented `bootstrap()` (GET /api/user/profile), `login()` (POST /api/auth/login), `signup()` (POST /api/auth/signup, token-only, no auth transition), `activateSession()`, `sendOTP()`, `verifyOTP()`, `logout()`, `refreshProfile()` |
| `richhealth/App/RootView.swift` | Replaced static TabView stub with phase-based routing: `.launching` → ProgressView, `.unauthenticated` → NavigationStack { LoginView }, `.authenticated` → TabView |
| `richhealth/richhealthApp.swift` | Flipped `@main` from `ContentView()` to `RootView()` + injected `AppEnvironment` |
| `richhealth/Features/Auth/LoginView.swift` | Wired to `appEnv.auth` via environment; added error display; added "Create account" toolbar button → `navigationDestination` to SignupView |
| `richhealth/Features/Auth/LoginViewModel.swift` | Implemented `login(auth:)` with `APIError.userMessage` mapping |
| `richhealth/Features/Auth/SignupView.swift` | Full 4-step form (Account → Personal → Physical → Goals) + OTP verification step; `navigationBarBackButtonHidden` after account creation |
| `richhealth/Features/Auth/SignupViewModel.swift` | All signup fields; `submit(auth:)` calls `auth.signup()` then `auth.sendOTP()`; `verifyOTP(auth:)` / `skipOTP(auth:)` call `auth.activateSession()` |
| `richhealth/Features/Profile/ProfileView.swift` | Reads profile from `appEnv.auth.currentUser`; uses `appEnv.auth.logout()` (no longer creates a new AuthManager) |
| `richhealth/Features/Profile/ProfileViewModel.swift` | Fixed: `load(auth:)` reloads via `auth.refreshProfile()` instead of creating a new `AuthManager()` |

### What changed

**Foundation wiring (Phase 0 → 1 transition):**
- `@main` now shows `RootView`, which routes on `AppEnvironment.phase`
- `AppEnvironment` embeds `AuthManager` so all views access `appEnv.auth` from one `.environment` object
- Token validation at launch: `bootstrap()` calls `GET /api/user/profile`; 401 → logout; network error → trust stored token (no false offline logouts)

**Auth flow:**
- Login: `POST /api/auth/login` → token → Keychain → `isAuthenticated = true` → `loadProfile()`
- Signup: `POST /api/auth/signup` → token stored in Keychain but `isAuthenticated` intentionally left `false` so `SignupView` stays visible for OTP verification before transitioning to main tabs
- `activateSession()` sets `isAuthenticated = true` and loads profile; called after OTP verified OR skipped
- OTP: `POST /api/auth/send-otp` / `POST /api/auth/verify-otp` — both `requiresAuth: false`; alreadyVerified short-circuit activates session immediately
- Logout: clears Keychain token + `currentUser`; `AppEnvironment.phase` drops to `.unauthenticated` automatically

**Signup multi-step form:**
- Step 0: Account (name, email, phone optional, password × 2)
- Step 1: Personal (gender segmented picker, DOB graphical DatePicker)
- Step 2: Physical (height/weight Steppers, metric)
- Step 3: Goals (primary goal, activity level, diet type — all `Picker(.menu)`)
- Activity levels 1–5 mirror Android's card options: Mostly Sitting → Athlete
- Diet options include "No Preference" (not in Android — iOS addition for users without a specific diet)
- OTP step shown after account creation; back button hidden; "Skip for now" calls `activateSession()`

**Profile:**
- `ProfileView` reads `appEnv.auth.currentUser` directly; no duplicate fetch
- `ProfileViewModel.load(auth:)` only reloads if `currentUser == nil`

### Why

Phase 1 goal: app boots to the correct place (login or main tabs) and auth flow runs end-to-end. The OTP-before-transition design (token stored but session not activated until OTP/skip) mirrors Android's `awaitingOtpVerification` pattern without blocking the user if they abandon OTP mid-flow — on next launch `bootstrap()` finds the valid token and lets them in.

Backend paths confirmed against `../richhealthbackend/index.js` route mounting:
- `app.use("/api/auth", authRoutes)` → `/api/auth/login`, `/api/auth/signup`, `/api/auth/send-otp`, `/api/auth/verify-otp`
- `app.use("/api/user", userRoutes)` → `/api/user/profile`
