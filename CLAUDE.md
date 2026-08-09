# CLAUDE.md — RichHealth iOS

## §26. Global branded loader (owner decision — one blocker for every REST call)
The app shows ONE branded UI blocker for every network call — the iOS port of Android `SimpleProgress`.
- **Component:** `DesignSystem/Components/BrandedLoaderView.swift` — full-screen tint veil (`Rectangle().fill(.ultraThinMaterial).opacity(0.70)`; the `.glassEffect(.clear)` pane looked wrong, don't use it here) + centered `GlassCard` with the `AppLogo` spinning 0→360°/2s, a message, and teal "RichHealth AI".
- **The global loader renders BEHIND any `.sheet`.** So it's ONLY for full-screen contexts. It stays on (`showsLoader` default true) for a small set: auth (login/signup/OTP/bootstrap/loadProfile/pro-access/usage), HealthHub tab `getStats` ×2, Profile tab `relationships`. **Everything else uses `showsLoader: false`** — every sheet-triggered call (all HealthHub/Services sheets, chat history, family, profile edit/memories, paywall) and every Services-dashboard read (they'd block the tab for the slowest call — up to ~45s).
- **Long / dashboard reads → inline, not the blocker.** Services dashboard uses per-card loading flags (`isLoadingBriefing`, `isLoadingDietary`, …) so each card clears when ITS data lands; a small `InlineLoader` (`ProgressView().controlSize(.small)`) sits after each card heading. Never gate all cards on one `isLoading`.
- **Silent (no loader):** also `showsLoader: false` for fire-and-forget / background / polling — analytics events, AQI store, NutriCheck feedback, report status poll. `sendMultipart` takes `showsLoader:`/`loaderMessage:` params (report upload is off — the sheet shows its own state).
- **Messages:** `Endpoint.loaderMessage` is specific + honest (e.g. "Saving medication…"). `LoadingController` shows the most recent active one. Kept on every endpoint even when `showsLoader:false` (harmless, ready if it ever goes full-screen).
- **Arg order:** `Endpoint(path:, method:, query:, body:, requiresAuth:, showsLoader:, loaderMessage:)` — `showsLoader`/`loaderMessage` go LAST. Putting `showsLoader:` right after `path:` fails to compile when `method`/`query`/`body` follow.
- **Driven by `Core/LoadingController.swift`** (`@MainActor @Observable`, counter-based). `APIClient.send`/`sendMultipart` call `.begin()` before the call and `.end()` in a `defer` — so it clears on success OR failure, and concurrent calls share one loader.
- **Mounted once** in `RootView` (`.overlay` on the root Group). Do NOT add per-screen loaders for network calls — the global one covers them. Adding a second overlay = double-stack.
- **Opt-out:** set `Endpoint(showsLoader: false)` for calls that have their own progress UI. Currently exempt: chat `sendMessage` + first-send `createSession` (thinking bubble). Pull-to-refresh keeps the loader unless owner says otherwise.
- Change the look ONLY in `BrandedLoaderView`; every screen updates automatically.
- Skeletons/`.loadingOverlay` are superseded for network state. `.skeleton` may still be used for non-network placeholder shimmer if ever needed, but never hardcode `isActive: true`.

> This file is the operating manual for any AI (or human) working in this iOS repo.
> It is paired with **NATIVE_COMPONENTS.md** (the Android→iOS native mapping). Read both before writing code.
> Companion codebases you can read directly (do **not** copy code, read them to learn behaviour):
> `../richhealth_android` (source app) and `../richhealthbackend` (the API — the source of truth).

---

## ⚠️ CRITICAL — READ BEFORE EVERY ACTION (non-negotiable, enforced by owner)

These rules were added after repeated violations caused broken builds and missing features. **No exceptions.**

### C1. Grep before removing ANY shared code.
Before deleting or renaming a function, modifier, struct, or constant from `DesignSystem/`, `Core/`, or `Models/` — run a full-project grep for the identifier. Confirm zero live call sites **before** the deletion. If there are call sites in files you haven't read, read them first, fix them, then delete. Never assume you know all the places a shared symbol is used.

### C2. §21 (3-agent pre-implementation research) is MANDATORY, not optional.
**Every time** you are about to write a View, ViewModel, or Service for any feature — no matter how small — you must first fan out three parallel agents:
1. **XML agent** — reads ALL Android layout XML files for that feature.
2. **Java agent** — reads the Android Activity/Fragment Java source.
3. **iOS state agent** — reads the current iOS implementation.

Skipping this is what caused: missing signup fields, wrong API endpoint paths, absent model selector, and profile header that looked nothing like Android. The pre-research is not overhead — it is the work.

### C3. Visual consistency is all-or-nothing on a given screen.
If you give TextFields a background treatment (`Color.secondary.opacity(0.1)` + `RoundedRectangle`), every other interactive control on that screen (Pickers, Steppers, DatePickers, Sliders) must get the **same** treatment. Inconsistent control styling on the same screen is a visual regression. Fix all instances, not just the one you changed.

### C4. Richie model selector — confirmed implemented.
The Richie input bar has a model-selector pill (sparkles icon + model name + chevron). Tapping opens `ModelPickerSheet`. Free models: `auto`, `gemini`, `mistral`, `deepseek`, `llama`. Pro-gated: `gpt5.3`, `claude4.5`. The backend accepts `modelType` in `POST /api/chat/sessions/:id/messages`. Do not re-implement or duplicate this; extend it.

### C5. Bottom sheet glass background.
All `.sheet` presentations in this app use `.presentationBackground(.thinMaterial)`. This is the correct iOS 26 glass appearance for sheets — do not change it to `.white` or `Color.clear`. If a sheet looks flat, investigate before touching the presentationBackground.

### C6. Do NOT invent features not present in Android.
Every data field, UI element, or interaction you add must exist in EITHER the Android XML layouts OR the backend schema. Do not add things (BMI calculation, completion gauge, etc.) just because they seem helpful — if Android didn't show it on that screen, it doesn't belong there without explicit owner approval.

### C7. StatusPill is for STATUS SIGNALS only (§12). Never use it as a data label.
Numeric values, metric readings, names, and plan badges that are not health/system status signals must use `Text()` or `LabeledContent`, not `StatusPill`. Re-read §12 before placing any pill.

### C8. Cosmetic tweaks must use native APIs — never fight the framework or over-engineer.
When adjusting row height, spacing, icon size, corners, or padding, reach for the **native SwiftUI list/layout modifiers** first — e.g. `.environment(\.defaultMinListRowHeight, …)` (List enforces a 44pt row minimum by default), `.listRowInsets(…)`, `.listRowSeparator(…)`, `.controlSize(…)`. Do **not** hack fixed `.frame(height:)` values that fight the framework, disable native behaviors (scrolling, swipe actions, selection) for a purely visual result, or spin up a custom component when a modifier suffices. If a "simple" cosmetic change starts requiring custom gesture/layout code, stop — you're over-engineering; find the native modifier.

---

## §25. Screen-by-Screen Audit Protocol (mandatory for all screens)

Before implementing OR fixing any screen, run this 5-step audit. Record results in a comment block at the top of the relevant View file, or in a scratchpad section below. **Never code from memory or assumption.**

### Step 1 — iOS Inventory Agent
Spawn an `Explore` agent to read the current iOS View + ViewModel. Produce an exhaustive flat list of:
- Every section, card, row, button, label, icon
- Every data field displayed (field name + source)
- Every action (tap, swipe, sheet open, API call)
- Every state (loading, empty, error, conditional visibility)
- Every navigation destination

### Step 2 — Android XML Agent
Spawn an `Explore` agent to read ALL layout XML files for that screen (fragment_*.xml, dialog_*.xml, item_*.xml, layout_*.xml related to this feature). Produce same flat list format.

### Step 3 — Android Java Agent
Spawn an `Explore` agent to read the Activity/Fragment Java. Add to the list:
- Click handlers and what they do
- Conditional visibility logic
- Edge cases (rate limits, empty states, warnings, stale-data banners)
- API calls and parameters

### Step 4 — Gap Analysis (synthesise in main context)
Create two lists: **In Android, missing from iOS** | **In iOS, not in Android (invented)**. For invented items — remove them unless the owner explicitly approved. For missing items — plan the native iOS equivalent.

### Step 5 — Implement + Verify
Implement fixes. Then re-run Step 1 agent on the updated file and confirm the gap list is empty. Log everything in `AI_CHANGE_LOG.md`.

---

## 0. Context — what these repos are

There are **three** sibling repos under `Desktop/Richhealth/`:

| Folder | What it is | Role here |
|---|---|---|
| `richhealthbackend/` | Node/Express + MongoDB (Mongoose) API | **Source of truth.** iOS talks to this. Do not assume a contract — read the route/controller. |
| `richhealth_android/` | Native Android, Java (Volley/OkHttp), SQLite, bottom nav | The app we are re-building. Reference for *behaviour and features*, **not** for structure. |
| `richhealth/` | This iOS Xcode project (SwiftUI, Xcode 26.6) | The target. Was an empty scaffold; we are building it properly. |

This is **not** a line-by-line port. It is a *smart migration*: keep the features and the backend contract, drop Android's mistakes (local DB, dead code, hardcoded URLs, side panels), and rebuild every surface with the most native iOS pattern available.

---

## 1. Locked decisions (do not re-litigate without asking the owner)

1. **iOS 26.5 minimum** (already set: `IPHONEOS_DEPLOYMENT_TARGET = 26.5`). Target Dynamic-Island–class iPhones. Use **Liquid Glass** natively — no fallback code paths for older OSes.
2. **SwiftUI + MVVM + a lightweight Router.** No heavy third-party frameworks (no TCA, no RxSwift, no Alamofire). Small, native, testable.
3. **Stateless client. Backend is the source of truth.** **No local database.** Android's SQLite (`DatabaseHelper.java`) is deliberately *not* migrated — it is dead weight there and we will not recreate it. The only persisted things allowed on device: the **auth token in Keychain**, and a few **non-sensitive UI flags in UserDefaults** (e.g. `didCompleteOnboarding`). Neither is a "database."
4. **Networking = async/await `URLSession`.** One `APIClient`, one base URL, Bearer token injected from Keychain. No hardcoded per-file URLs (Android's #1 bug — see §7).
5. **Concurrency:** project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. ViewModels are `@Observable` `@MainActor`; network work is `async` and hops off-main inside `APIClient`.

---

## 2. Golden rules (the owner's working style — follow exactly)

- **Reply SHORT.** Keep chat answers brief and to the point — no long essays, no option surveys. Give the conclusion, not the walkthrough.

- **Check files. Do not assume.** Before you claim the app does X, open the relevant file in `../richhealth_android` or `../richhealthbackend` and confirm. Reference the file by path in your reasoning.
- **Don't re-invent the wheel.** Before building something, check whether it already exists in this repo. If a screen/model/service is present, extend it — don't duplicate.
- **Don't break anything.** This Xcode project is a **file-system synchronized group** — every `.swift` file under `richhealth/` is auto-compiled. A stray file that doesn't compile breaks the build. Keep every file compiling.
- **Reference files, not pasted code.** When writing rules or tasks, name the file + the rule. Don't paste large Android code.
- **Look for inconsistencies** in any request and surface them before acting.
- **Double-check before doing anything not explicitly asked.** If a change touches something outside the ask (schema, entry point, backend), stop and confirm.
- **Never skip provided files.** If given files/screens, account for every one.
- **Log every change** in `AI_CHANGE_LOG.md` (datestamp, files, what, why) — mirror the discipline already used in `../richhealth_android/AI_CHANGE_LOG.md`.
- Prefer native components first; only build custom when no native equivalent exists (see NATIVE_COMPONENTS.md).
- **Fix holistically — never patch one thing in isolation.** If a gap exists in one screen, check all screens. Document everything fixed in `AI_CHANGE_LOG.md`. (See §24.)
- **Run the §22 UX coherence checklist** after every phase before reporting done. This includes: first-run state, permission timing, visual consistency, edge cases from Android.

---

## 2A. Consistency & reuse (read before building any UI or function)

**Search this repo before you write anything.** If a shared `View`, modifier, service, or function already exists (`DesignSystem/`, `Core/`, `Models/`, a feature folder), **reuse or extend it — never write a second way to do the same thing.** If you write the same view/logic twice, extract it into `DesignSystem/Components` or `Core/`.

**One canonical pattern per concept — decide once, use everywhere.** Android's mistake was solving the same problem multiple ways (side panels *and* dialogs, different card and picker treatments per screen). We do not repeat that.

- **Cards** → always `GlassCard`. Never a hand-rolled VStack here and a Form row there for the same thing.
- **Selection/pickers** → always `Picker`/`Menu` (or the one shared selectable-card component). Don't mix a wheel on one screen and a menu on another for the same kind of choice.
- **Drawers** → always a bottom `.sheet` with detents. Never a side panel; never a full-screen cover for what is really a sheet.
- **Confirm → `.alert`; choice list → `.confirmationDialog`; form → `.sheet`** (NATIVE_COMPONENTS §3). Same trigger type ⇒ same control, every screen.
- **Loading → `.skeleton(isActive:)`. Empty → `ContentUnavailableView`. Errors → one shared error presentation.**

**Consolidate CTAs (thinner, standard lists).** Collapse per-row actions into **one** native overflow control — a `Menu` behind an ellipsis (`ellipsis.circle`) or `.swipeActions`. Don't scatter several inline buttons per row (Android's rows were fat and inconsistent). One CTA entry point per row → thinner, consistent list views. One prominent primary button per screen (`.borderedProminent`); everything else goes in the overflow menu or the toolbar.

**Edge-case parity — never ship a happy-path-only screen.** Before migrating a screen, read its Android file, list the edge cases it handles, and handle the **same** ones natively: empty data, `429`/`403` limits → paywall, stale/old-data warnings, sparse-data hints, missing fields, offline, neutral (not falsely-positive) default states. Many are documented in `../richhealth_android/AI_CHANGE_LOG.md` (e.g. the chat limit dialog, "data may not be current" symptom-age warnings, profile-completion, neutral health-status defaults). **Port the intent, not the code.** A cleaner native design may cover a case more simply — fine, but never drop the case.

**Comment style — short and migration-useful only.** One line, only where it helps migration: which backend endpoint a call maps to, which Android file/behaviour it replaces, why a native choice was made, or a `TODO`. No narration of obvious Swift.

---

## 3. Architecture & folder layout

MVVM with a single navigation Router per tab. One folder per feature; each screen owns a `View` + an `@Observable ViewModel`; data access goes through a small per-domain `Service` that calls `APIClient`.

```
richhealth/richhealth/            ← file-system synchronized group (auto-compiled)
├── richhealthApp.swift           ← @main (currently shows ContentView; flip to RootView when ready)
├── ContentView.swift             ← original template (leave until RootView is wired)
├── App/
│   ├── RootView.swift            ← TabView (Liquid Glass bottom pill) with the 4 tabs
│   └── AppEnvironment.swift       ← @Observable app state (auth/session), injected via .environment
├── Navigation/
│   └── Router.swift              ← Route enum + @Observable Router (NavigationStack path per tab)
├── Core/
│   ├── Networking/
│   │   ├── APIConfig.swift       ← base URL (single source), paths
│   │   ├── APIClient.swift       ← async request<T: Decodable>, Bearer injection, 401/403/429 handling
│   │   ├── Endpoint.swift        ← Endpoint + HTTPMethod
│   │   └── APIError.swift        ← typed errors (unauthorized, limitReached(429), notAllowed(403), ...)
│   └── Auth/
│       ├── KeychainStore.swift   ← tiny Keychain wrapper (token only)
│       └── AuthManager.swift     ← login/logout/token state (@Observable)
├── DesignSystem/
│   ├── Theme.swift               ← colours, spacing, typography (teal brand)
│   └── Components/
│       ├── GlassCard.swift       ← .glassEffect card wrapper
│       ├── StatusPill.swift      ← replaces Android StatusPill/PlanBadge
│       ├── UsageRing.swift       ← replaces Android UsageRing (native Gauge)
│       └── SkeletonModifier.swift← .redacted shimmer (replaces Android Skeleton)
├── Models/                       ← Codable DTOs that mirror backend responses
│   ├── UserProfile.swift
│   ├── AuthModels.swift
│   └── ChatModels.swift
└── Features/
    ├── Auth/            (LoginView/‑VM, SignupView/‑VM)
    ├── Onboarding/      (OnboardingView/‑VM)
    ├── Richie/          (RichieView/‑VM — the AI chat tab)
    ├── HealthHub/       (HealthHubView/‑VM — vitals/health data)
    ├── Services/        (ServicesHomeView/‑VM — the "Services"/home tab)
    ├── Profile/         (ProfileView/‑VM)
    └── Paywall/         (PaywallView — Pro upgrade; see §10 payment decision)
```

Rules for this structure:
- A `View` never calls `URLSession` directly. It calls its `ViewModel`; the VM calls a `Service`; the `Service` calls `APIClient`.
- No singletons for state except `AuthManager`/`AppEnvironment` (injected through the environment).
- DTOs in `Models/` must match the backend JSON exactly — verify against the controller in `../richhealthbackend/controllers`.

---

## 4. Networking & the REST-call lifecycle (the "when to call" rule)

**Where REST calls happen in the SwiftUI lifecycle** — this is deliberate and efficient, and is the opposite of Android's "fetch in every `onResume`":

- **Initial load per screen:** use `.task { await vm.load() }` on the view. `.task` runs once when the view appears and **auto-cancels** when it disappears — no leaked requests (Android leaked Volley requests on fragment swaps).
- **Parameter-driven reload:** `.task(id: someID) { … }` re-runs only when the id changes. Don't reload on every tab switch.
- **Session caching:** a ViewModel holds its fetched data for the app session. Switching tabs must **not** refetch. Only refetch on explicit user action or a known invalidation (e.g. after a profile edit).
- **Pull to refresh:** `.refreshable { await vm.reload() }` — the only routine manual refetch.
- **App launch:** `AuthManager` reads the token from Keychain, then validates via `GET /api/user/profile`. Valid → go to `RootView`; missing/401 → `LoginView`. Do this once, at the root, not per tab.
- **Cross-screen freshness:** when an edit changes shared data (profile, pro status), update the in-memory model and post a lightweight signal (e.g. a value on `AppEnvironment`) instead of re-hitting the network everywhere.
- **Auth header:** injected centrally in `APIClient` from Keychain. Never per-call, never hardcoded.
- **Backend limit signals:** `429` → `APIError.limitReached`, `403` → `APIError.notAllowed`. Surface these as the Paywall/upgrade sheet, not a generic error (Android learned this the hard way — see `../richhealth_android/AI_CHANGE_LOG.md` 2026-03-24).

---

## 5. Native-first rule

Every Android surface must be rebuilt with the most native iOS control available. The full table lives in **NATIVE_COMPONENTS.md**. Summary of the big ones:

- Android **bottom navigation** → SwiftUI **`TabView`** (iOS 26 renders the Liquid Glass floating bottom pill automatically). Do not build a custom tab bar.
- Android **side panels** (`layout_side_panel.xml`, `layout_*_panel.xml`) → native **bottom sheets** (`.sheet` + `.presentationDetents`) or a `NavigationStack` push. Side panels are not an iOS idiom; sheets/drawers are.
- Android **custom dialogs** (`DialogUtils.java`, all `dialog_*.xml`) → native **`.alert`**, **`.confirmationDialog`**, or **`.sheet`**. If it's a yes/no, it's an alert; if it's a form, it's a sheet.
- Android **bottom sheet** (`UsageBottomSheet`) → native `.sheet` with detents.
- **Charts** (`dialog_aqi_chart`, `report_trend_chart`) → **Swift Charts**.
- **Biometric** (`BiometricHelper.java`) → **LocalAuthentication** (Face ID / Touch ID).
- **Markdown in chat** (`TextFormatter`, `MarkdownChunker`) → `AttributedString(markdown:)` (native).
- **Skeleton loaders** (`Skeleton.java`) → `.redacted(reason: .placeholder)`.

If no native equivalent exists, pick the closest native pattern and record the decision in NATIVE_COMPONENTS.md before coding.

---

## 6. Feature migration map (Android → iOS)

Live navigation in Android (from `../richhealth_android/UNUSED_CODE_REPORT.md` §12) is: Splash → Login/Signup → MainActivity with a 4-tab bottom nav. Current tab labels (from `res/menu/bottom_navigation_menu.xml`) are **Richie · Health Hub · Services · User**.

| iOS feature | Android source (reference only) | Backend (source of truth) | Notes |
|---|---|---|---|
| Auth (Login/Signup) | `LoginActivity.java`, `SignupActivity.java` | `POST /api/auth/login`, `POST /api/auth/signup` | Token → Keychain. Signup is multi-step. |
| Onboarding | `OnboardingActivity.java` + `Onboarding*Fragment.java` | folded into signup/profile | Multi-step paged flow. |
| Richie (AI chat) — tab 1, default | `AIFragment.java` (~196KB — the biggest) | `POST /api/chat/send`, `chatRoutes.js` | Ignore the dead legacy session flow (§7). Chat history panel → sheet. |
| Health Hub (vitals) — tab 2 | `HealthDataFragment.java` (~243KB) | `medicalDataRoutes`, `medicationRoutes`, `symptomRoutes`, `periodLogRoutes`, `medicalReportRoutes` | Six Android side panels here → six native sheets. |
| Services (home) — tab 3 | `HomeFragment.java` (~218KB) | `homeScreenRoutes`, `feedRoutes`, `aqiRoutes`, `doctorRoutes`, `workoutRoutes` | Cards: health feed, AQI, NutriCheck, workouts, link-doctor. |
| Profile — tab 4 | `ProfileFragment.java` (~154KB) | `GET/PUT /api/user/profile`, `paymentRoutes` | Edit profile → sheet, not a side panel. |
| Health Analysis | `HealthAnalysisActivity.java` | `healthAnalysisRoutes` | Charts via Swift Charts. |
| Doctor search/connect | `DoctorSearchActivity` + doctor fragments | `doctorRoutes`, `doctorAuthRoutes` | |
| Paywall / Pro | `ProUpgradeDialog.java` (~79KB), `PaymentManager/Service` | `paymentRoutes` | **Payment method is an open decision — see §10.** |
| Daily check-in | `DailyCheckInActivity.java` | `checkInRoutes` | |
| NutriCheck | `NutriCheckActivity` + fragments | `POST /api/home/nutri-check` | Enforce 429 limit → paywall. |

Verify each endpoint's exact shape in the matching controller before building the DTO. `../richhealth_android/RichHealthExpress_Complete_System_Analysis.md` has a full endpoint catalogue, but the controller wins if they disagree.

---

## 7. What NOT to migrate

- **Local SQLite / `DatabaseHelper.java`** — dropped by decision (§1.3). Stateless client.
- **All dead code** listed in `../richhealth_android/UNUSED_CODE_REPORT.md`: `ToolsFragment`, `MedicalReportsDialogFragment`, `EditProfileActivity`, `CustomPodcastActivity`, the AIFragment legacy session flow (`createOrGetSession`/`syncMessagesFromBackend`/`loadChatHistory`/`showModelDropdown`), the ProfileFragment family-records duplicate, and the 17 dead Java files / 19 dead layouts. Do not port unreachable features.
- **Hardcoded base URLs** — Android had the URL pasted in ~13 places across 5 files (`PaymentService.java` etc.). iOS has exactly one: `APIConfig.baseURL`.
- **Android's broken booleans** — e.g. the `ProStatusManager.isProUser()` logic bug. Re-derive Pro state from the server (`GET /api/user/pro-access`), don't copy the local logic.
- **Volley/OkHttp patterns** — replaced wholesale by `APIClient`.

---

## 8. Backend contract (quick reference — always confirm in the controller)

- **Base URL:** `https://richhealthbackend.vercel.app` (the value Android currently ships in `Utils/ApiConfig.java`). Put it in `APIConfig.baseURL`.
- **Auth:** JWT Bearer in `Authorization` header. Obtained from `/api/auth/login` or `/api/auth/signup`. Stored in Keychain.
- **Note the path quirk:** profile is `/api/user/profile` (singular `user`) in `ApiConfig.java`; some routes use `/api/users/*`. **Confirm each path** against `../richhealthbackend/routes/*` — do not guess.
- Route groups (see `../richhealthbackend/routes/`): `auth, users, user/doctor, doctor, doctor-auth, payment, medical-data, medications, medical-reports, chat, checkIn, symptom, periodLog, feed, home, aqi, exercise, workout, dependent, healthAnalysis, contacts(placeholder)`.
- **Pending backend work** is described in `../richhealth_android/BACKEND_CHANGES_PROMPT.md` (monthly usage reset, NutriCheck 429 enforcement, genetics analysis, cache health screening, remove dead `overallHealthAnalysis`, etc.). Treat that file as a backlog: if an iOS feature depends on one of those, verify whether it's been applied in `../richhealthbackend` **before** relying on it.

---

## 9. Roadmap (build in this order)

**Phase 0 — Foundation (do first, no UI features).**
Networking (`APIClient`, `APIConfig`, `Endpoint`, `APIError`), `KeychainStore`, `AuthManager`, `AppEnvironment`, `Router`, `RootView` (4-tab Liquid Glass shell), DesignSystem primitives. Wire `@main` → `RootView` once the shell compiles and runs.

**Phase 1 — Auth + shell.**
Login, Signup (multi-step), token persistence, launch-time token validation, logout. App boots to the correct place.

**Phase 2 — Richie (AI chat) tab.**
Chat send/receive, markdown rendering, thinking state, history as a sheet, 429/403 → paywall. (Ignore Android's dead session code.)

**Phase 3 — Health Hub tab.**
Vitals, medications, symptoms, medical data, reports, period logs — each Android side panel becomes a native sheet. Charts via Swift Charts. File upload for reports.

**Phase 4 — Services (home) tab.**
Health feed, AQI card + chart, NutriCheck (with limit), workouts, link-doctor flow.

**Phase 5 — Profile tab + Paywall.**
Profile view/edit (edit = sheet), Pro status from server, upgrade flow (**pending §10 decision**), biometric lock.

**Phase 6 — Polish.**
Daily check-in, doctor search, dependents, notifications, empty/error/skeleton states, accessibility, Dynamic Island Live Activity if warranted.

Each phase: build native, verify against the backend controller, log to `AI_CHANGE_LOG.md`, keep the project compiling.

---

## 10. Open decisions & inconsistencies (resolve with the owner before affected work)

1. **Payment method (blocking Phase 5).** Android sells Pro via **UPI intents (Paytm/Razorpay)** launching external apps. iOS has **no UPI intent system**, and — more importantly — Apple's App Store guidelines generally require **digital subscriptions to use In-App Purchase (StoreKit 2)**. Selling Pro via UPI/Razorpay inside the iOS app risks rejection. Options: (a) StoreKit 2 IAP (App-Store-compliant, needs backend receipt validation + new endpoints), (b) UPI deep links via `UIApplication.open` (fast, likely non-compliant for digital goods), (c) treat Pro as an external/web purchase. **Do not pick silently — ask the owner.**
2. **Tab labels drift.** `bottom_navigation_menu.xml` says *Richie · Health Hub · Services · User*, but `UNUSED_CODE_REPORT.md` §12 (Feb 2026) calls them *Home · Vitals · Richie · Profile*. A relabel happened. This doc uses the menu XML (current). Confirm final iOS tab names/order with the owner.
3. **"Services" vs "Home".** The `navigation_home` id maps to the "Services" tab which loads `HomeFragment`. Naming is confusing in Android; pick clean iOS names.
4. **Backend path inconsistency** (`/api/user/profile` vs `/api/users/*`) — resolve per route against `../richhealthbackend/routes` and standardise the iOS `Endpoint` values.
5. **Request wording note:** the original migration brief said "fill it natively **here in android**" — read as **iOS** (this repo). Recorded so it isn't taken literally.

---

## 11. Change-log discipline

Maintain `AI_CHANGE_LOG.md` at repo root. Every change: `## [YYYY-MM-DD] <summary>` then affected files, what changed, why. Another agent should be able to reconstruct intent from the log alone. Mirror the style of `../richhealth_android/AI_CHANGE_LOG.md`.

---

## 14. Design tokens — no hardcoded values (light/dark adaptable)

All visual constants live in `DesignSystem/Theme.swift`. Feature and component code **never** define colours, radii, or spacing inline.

**Colours:**
- Brand/custom colours → `Theme.*` (e.g. `Theme.brandTeal`). Add new ones to `Theme.swift` only.
- Content colours → SwiftUI semantic colours (`.primary`, `.secondary`, `.tertiary`, `.background`, `.fill`) — these flip automatically in dark mode. Never write `.red`, `.blue`, `.gray`, etc. in feature code unless it is a *deliberate*, *non-themeable* meaning (e.g. white text on a teal button for contrast — acceptable, but document why).
- Status signals → `StatusLevel` enum in `StatusPill.swift` (§12). Do not add a fifth semantic colour without updating §12.
- **Zero `Color(red:green:blue:)` calls outside `Theme.swift`.** If you need a new brand colour, add it there and name it.

**Materials / backgrounds:**
- Prefer adaptive materials (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`) for cards and surfaces — they automatically invert for dark mode and integrate with Liquid Glass.
- Never hardcode `Color.white` or `Color.black` as a *surface* colour. Use materials or semantic fills.

**Typography / spacing:**
- Spacing constants → `Theme.Spacing.s/m/l`. New sizes go there.
- Type styles → use SwiftUI's built-in type system (`.title`, `.body`, `.caption`, `.subheadline`, etc.) with `.weight()` modifiers. Do not hardcode font sizes as magic numbers. If a custom size is truly needed add it to `Theme`.

**Verification:** before opening a PR, run a grep for `Color(red:`, `Color(#`, `UIColor` across `richhealth/` — the only expected hit is `Theme.swift:brandTeal`.

---

## 16. Session cache policy — UserDefaults TTL (not a database)

Some API responses are expensive to re-fetch and change infrequently. Cache these in UserDefaults via `Core/Cache/SessionCache.swift`. This is the iOS equivalent of Android's SharedPreferences — a flat key/value store with expiry timestamps, **not** a relational database.

**What to cache (TTL) and why:**

| Data | TTL | Reason |
|---|---|---|
| Daily briefing (`"briefing"`) | Same calendar day (`loadToday`) | Backend regenerates once per day; re-fetching mid-day returns the same content |
| Daily digest advisory (`"digest"`) | Same calendar day | Daily rhythm content; city context only changes with location |
| Dietary insights (`"dietary"`) | 8 hours | Changes when user logs new health data, but not more often than a few times per day |
| AQI + resolved city (`"aqi"`) | 1 hour | Air quality changes slowly; location geocoding is expensive and permission-gating |

**What NOT to cache:**
- Health records (symptoms, measurements, medications) — user may edit from another device
- Chat sessions and messages — real-time, session-sensitive
- Feed items — content is fresh and paginated
- Workouts, doctors — transactional, should always be current
- Auth token — lives in Keychain, not UserDefaults

**Splash warmup + cache-first (briefing/digest/dietary):** `AppEnvironment.startupDataWarmup()` prefetches these into SessionCache during the 2.5s splash floor (and keeps running after). `ServicesHomeViewModel` is **cache-first** for these three — a fresh entry (same-day / 8h) is authoritative, shown instantly with NO re-fetch (avoids the ~26s/~46s calls every launch). This deviates from the SWR pattern below **for these three only**; pull-to-refresh (`reload()` → `clearAll()`) still forces fresh. All other cached data keeps SWR.

**Pattern — stale-while-revalidate (preferred for daily data):**
```swift
// Show cached data instantly, then update with fresh data silently.
if let cached = SessionCache.loadToday(BriefingResponse.self, key: "briefing") {
    briefingCards = cached.cards
}
if let r = try? await insightsService.fetchBriefing() {
    SessionCache.save(r, key: "briefing")
    briefingCards = r.cards
}
```

**Pattern — hard TTL (for location-gated data like AQI):**
```swift
if let cached = SessionCache.load(AQIBundle.self, key: "aqi", maxAge: 3600) {
    // Show cached result; skip the entire location permission + geocode + API flow.
    return
}
// Cache miss: proceed with location request.
```

**Lifecycle rules:**
- Call `SessionCache.clearAll()` on `reload()` (pull-to-refresh) so the user always gets fresh data on explicit refresh.
- Call `SessionCache.clearAll()` on **logout** so cached data never leaks between accounts.
- Do NOT add a session-flag to clear caches on cold launch — the TTL handles that automatically. Same-day entries expire at midnight; hourly entries expire after 60 min regardless of app lifecycle.

---

## 17. Brand teal usage — where `Theme.brandTeal` goes (and where it doesn't)

`Theme.brandTeal` is the single brand accent. It has a specific role — overuse dilutes it.

**Use teal for:**
- **Category labels** on cards and list rows — `Text(item.category.uppercased()).foregroundStyle(Theme.brandTeal)` — makes categories scannable and visually anchors content type
- **Interactive text elements** — "Read more", "See all", "NutriCheck" inline buttons
- **Primary branded icons** — the Richie sparkles, the logo in the toolbar
- **Active states** — selected tab, focused input ring (via `AccentColor`)
- **Primary action button tint** — `.tint(Theme.brandTeal)` on `.borderedProminent` buttons

**Do NOT use teal for:**
- Section headers (use `.headline` with `.primary` foreground — default)
- Sub-labels or metadata (use `.secondary` or `.tertiary`)
- Body copy or advisory text
- Status signals (use `StatusLevel` enum — §12)
- Error text (use `.red` with a `// error feedback` comment)
- Decorative dividers or backgrounds

**Rule:** If removing the teal color from an element would make the UI clearer, it shouldn't be teal. Teal draws the eye — reserve it for things that deserve attention.

---

## 18. Layout density and card consistency rules

### Full-width lists over grids for text-heavy content
- **Suggestions, results, health records** → full-width `VStack` rows with `HStack { content; Spacer(); trailing-icon }` layout.
- **Two-column grids are only appropriate** for icon-primary items (e.g., a feature launcher grid) where each cell is roughly square and visual hierarchy is symmetric.
- Rationale: on iPhone, a 2-column text grid produces cramped cells with line-wrapping that hurts readability and increases mis-tap rate. Full-width rows let text breathe and are easier to scan.

### Card height consistency
- **GlassCard inner content** must have `.frame(maxWidth: .infinity, alignment: .leading)` on the root VStack — this ensures cards stretch to screen width even when content is short.
- Cards that have dramatically different heights between states (loading, empty, loaded) should add `minHeight` to prevent layout jumps: `.frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)`.
- **Empty states inside cards** → use an inline `HStack { Image; Text }` rather than `ContentUnavailableView`. `ContentUnavailableView` is a full-screen centred layout — it is large and creates visual inconsistency when embedded in a card. Use it only for full-screen empty states (whole tab is empty).

### Expand / collapse for long text
- Advisory or AI-generated text that may exceed 3 lines should use a `@State var isExpanded` toggle with `.lineLimit(isExpanded ? nil : 3)` and a `Button("Read more")` / `Button("Show less")` in `Theme.brandTeal`.
- Animate the toggle: `.animation(.easeInOut(duration: 0.2), value: isExpanded)`.
- This keeps card height predictable in the collapsed state while allowing access to full content.

### Animated branding in feature headers
- The Richie tab uses a continuously rotating logo (`Image("AppLogo")`, 6 s/rev) placed **above the greeting/salutation in the empty state**, not in the toolbar. The `.principal` toolbar slot shows only the active session title.
- Do not add decorative animations to Health Hub, Services, or Profile — Richie is the AI feature and the animation is semantic (indicates the AI is alive and thinking), not merely cosmetic. Keep other tabs static.

---

## 15. Agent parallelism — use parallel subagents for multi-step tasks

When a task involves three or more **independent** sub-steps (reading multiple backend files, auditing multiple screens, migrating multiple routes), **fan out with the `Agent` tool in a single message** so they run concurrently, then synthesise the results. Do not do these sequentially in the main context.

Patterns:
- Research → spawn one Explore subagent per target file/route, all in one message.
- Multi-screen migration → spawn one agent per screen (with `isolation: "worktree"` if they write to the same files).
- Cross-file audits → spawn parallel read agents, then synthesise before editing.

**When NOT to fan out:** simple edits to a single file, short lookups, or tasks where step B depends on step A's result — those stay sequential in the main context.

---

## 12. Status Pill design system — four canonical states (locked)

Every pill that conveys a health or system **status** must use one of exactly four levels. No other colours are allowed for status signals. This is implemented in `DesignSystem/Components/StatusPill.swift` via the `StatusLevel` enum.

| Level | Color | When to use |
|---|---|---|
| `.green` | Green | Good, healthy, normal, within limits, verified, active |
| `.yellow` | Yellow | Borderline, mild warning, pending, approaching a limit |
| `.orange` | Orange | Elevated, moderate concern, use-with-caution cases |
| `.red` | Red | Critical, bad result, expired, limit reached, hard error |

**Rules:**
- **Always use `StatusPill(text:level:)`** for any health metric, usage indicator, or system state signal.
- **Never invent a fifth colour** for a status meaning. If something doesn't fit the four levels, reconsider whether it is truly a status signal or just a label.
- **Non-status labels** (e.g. "Pro", "Beta") use `StatusPill(text:)` without a `level` — they default to brand teal and are intentionally NOT part of the four-state system.
- **One pill per concept, one colour per meaning.** The same state must always map to the same level everywhere in the app. For example, "Normal blood pressure" is always `.green`; "Stage 2 hypertension" is always `.red`.

**Quick reference for common mappings:**

| Signal | Level |
|---|---|
| Healthy / within range | `.green` |
| Pro / plan badge | no level (brand teal) |
| Nearing usage limit | `.yellow` |
| Usage limit reached | `.red` |
| Pending / unverified | `.yellow` |
| High AQI (moderate) | `.yellow` |
| High AQI (unhealthy) | `.orange` |
| High AQI (hazardous) | `.red` |
| Medication: active | `.green` |
| Medication: overdue | `.red` |
| Symptom: mild | `.yellow` |
| Symptom: severe | `.red` |

---

## 19. Swipe hint affordance — intentionally deferred

**Do NOT apply `.swipeHint()` to `List` rows.** The current `SwipeHintModifier.swift` implementation uses `.offset(x:)` on the row, which conflicts with UITableView's gesture recogniser system inside SwiftUI's `List`. This breaks scroll smoothness — rows stutter and the list no longer feels native.

**The file `DesignSystem/Components/SwipeHintModifier.swift` exists but is intentionally unused.** It must not be applied anywhere without first replacing the `.offset(x:)` approach.

**Cleaner alternatives to evaluate before re-implementing:**
- A one-time dismissible section header row ("← Swipe items for options") above the list, shown only on first use via a UserDefaults flag — no row animation, no gesture conflict.
- `.badge()` on the first row only — static indicator, no animation.
- No custom implementation — iOS users learn swipe actions from system apps (Mail, Messages, Reminders).

**Rule:** Never compromise list scroll smoothness for an affordance hint. If a hint implementation causes any scroll jank, drop the hint entirely.

---

## 20. Follow the complete user flow before implementing any feature

Before writing code for any feature, read **all three** sources in order:

1. **Android XML layouts** — `res/layout/<feature>*.xml` for the relevant Activity/Fragment. This shows the visual hierarchy, what controls exist, and what the user sees. Many edge cases (empty states, loading banners, status pills) are only discoverable here.
2. **Android Java/Kotlin source** — the Activity or Fragment that powers those layouts. Read the click handlers, lifecycle methods, and error paths. Understand what user actions trigger what flows.
3. **Backend controller** — `../richhealthbackend/controllers/<feature>Controller.js`. This is the source of truth for the API contract: exact path, request shape, response shape, error codes. Do not guess paths or field names.

**Only after reading all three** should you write the iOS ViewModel, Service, or View.

This rule exists because:
- Android XML reveals UX details not in the Java (e.g., placeholders, helper text, multi-step flows).
- The Android Java reveals edge cases (rate limits, empty states, warnings) that are easy to miss.
- The backend controller is the only authoritative source for API paths — Android source has hardcoded URLs that diverge from the actual server routes (the `/api/health/data` vs `/api/medical-data` mistake was caused by not reading the controller).

**For parallel research on 3+ routes**, use the `Agent` tool fan-out pattern (§15).

---

## 21. Mandatory pre-implementation research — 3 parallel agents

Before writing **any** screen, service, or ViewModel, fan out **three parallel agents** in a single message:

1. **XML agent** — reads ALL Android layout XML files for the target feature (`res/layout/<feature>*.xml`). Reports every widget, field type, hint text, row structure, section header, empty-state, error banner, chip group, and conditional visibility.
2. **Java agent** — reads the full Android Activity/Fragment Java source. Reports click handlers, lifecycle calls, validations, error paths, API calls, and edge cases (rate limits, empty results, conditionally shown sections).
3. **iOS state agent** — reads the current iOS implementation (View + ViewModel + Service). Reports what is already built, what patterns are already used (GlassCard, StatusPill, etc.), and what is missing vs. the Android source.

**Synthesise all three before writing a single line of code.** Write a short bullet list of what needs to be implemented, then act on ALL of them — not just the ones that are obvious.

**Why:** Surface-level reading misses most fields, edge cases, and input types. The signup/profile field gap (missing 20+ fields) and the Health Hub first-run error were caused by not following this process.

**For the SignupView specifically:** Android's `OnboardingActivity` is the PRIMARY signup flow (not `SignupActivity`). It uses **RecyclerView of selectable cards** for most selections (activity level, goals, diet, habits, blood type, conditions, sleep, stress). The iOS equivalent is a custom `SelectionCardGrid` component — NOT `Picker(.menu)`. This change is pending; do not implement menu pickers for multi-option selections without checking if a card grid would be more appropriate.

---

## 22. Post-implementation UX coherence check — mandatory before closing a phase

After implementing any screen or phase, run this checklist **before reporting done**:

1. **User flow coherence** — Trace the full user journey (e.g., "new user opens app → signs up → lands on Richie tab"). Does every transition make sense? Does the screen the user lands on match what they expect?
2. **First-run / empty state** — What does a brand-new user see? Are counts 0? Are there ContentUnavailableView or inline empty states (not errors)?
3. **Permission timing** — Does the screen request permissions (location, camera, biometric) at the right time, with a clear rationale, and handle denied gracefully? Location should be requested when the AQI card first loads, not silently fail.
4. **Visual consistency** — Does this screen use the same GlassCard, section label, icon-row, StatusPill, and sectionHeader pattern as existing screens? (§21 iOS state agent confirms this.)
5. **Error handling consistency** — Are errors shown the same way as other screens? Toast? `.alert`? Inline red text? Pick one and be consistent.
6. **Edge cases from Android** — Re-read the Java agent findings. Are all edge cases (rate limits, stale data warnings, pro gates, empty states) handled?
7. **Color/spacing audit** — Does the screen use only `Theme.*` colors and `Theme.Spacing.*`? Run a mental grep for `Color(red:`, `.red`, `.white`, `.black` literals without comments.
8. **Could this be done better?** — Is there an already-built component in `DesignSystem/` or another feature folder that could be reused? Does anything look inconsistent with what was already built?

If any check fails, **fix it before closing the phase**.

---

## 23. Debug logging — every REST call must log

`APIClient.swift` contains a `rhLog(_:)` function (`#if DEBUG` `print()`) that logs every network call. Format:

```
[RH] → METHOD  /path  (body)              ← request
[RH] ← STATUS  /path  (bytes, 342ms)      ← success (with response time)
[RH] ✗ STATUS  /path  (342ms) — message   ← error (4xx/5xx/transport/decode)
```

**Rules:**
- All logging goes through `rhLog()` — never add raw `print()` to service or ViewModel code.
- Use Xcode console filter `[RH]` to isolate network logs.
- Transport errors, decode errors, and status errors are all logged with the `✗` prefix.
- Multipart uploads include body size in the request log.
- Do NOT log auth token values, passwords, or PII in request bodies.

**Padding in Tab views:**
- iOS 26 Liquid Glass `TabView` automatically provides safe-area insets for its content. Do **NOT** add manual `.padding(.bottom, ...)` to tab root content — it will double the padding.
- If a `List` or `ScrollView` inside a tab appears to go under the tab bar, first check for `.ignoresSafeArea()` being applied unintentionally before adding manual padding.
- Sheets and presented views need their own bottom padding if they contain scroll content that risks going under system chrome.

---

## 24. Holistic fixing rule — never patch one thing in isolation

When a bug, gap, or inconsistency is found, **do not fix only that one thing**. Before writing any code:

1. Check whether the same issue exists in other screens (e.g., a color literal in one file probably exists in five others).
2. Check whether fixing one thing reveals a related gap (e.g., fixing first-run error in HealthHub means checking all other tabs for the same pattern).
3. Check whether the fix should be generalised into a shared component or rule (e.g., a resilient multi-load pattern should be extracted and reused, not inlined once).

**The fix is not done until all related instances are addressed.** Document what you found and fixed across ALL affected files in `AI_CHANGE_LOG.md`.

---

## 13. Continuing work in a new chat session

Paste the block below at the start of a new conversation to give the next agent full context. It replaces having to re-read all the files from scratch.

```
You are working inside the `richhealth` iOS Xcode project (SwiftUI, Xcode 26.6, iOS 26.5 min,
Swift 5, MainActor-default concurrency). Two sibling repos sit next to it and are READ-ONLY
references: `../richhealth_android` (the existing Android app) and `../richhealthbackend`
(the Node/Express + MongoDB API — the source of truth for all endpoints).

FIRST, before writing any code, read these binding files at the repo root:
- `CLAUDE.md` — architecture, rules, REST-call lifecycle, feature map, roadmap, open decisions.
- `NATIVE_COMPONENTS.md` — the Android→iOS native component mapping.
- `AI_CHANGE_LOG.md` — every change made so far; read it to know the current state.

COMPLETED SO FAR:
- Phase 0 (foundation): APIClient, APIConfig, Endpoint, APIError, KeychainStore, AuthManager,
  AppEnvironment, Router, RootView, all DesignSystem primitives, all Models stubs.
- Phase 1 (auth + shell): @main → RootView; phase-based routing; login/signup/OTP/logout;
  4-step SignupView; ProfileView uses injected auth; StatusPill with StatusLevel enum.
- Phase 2 (Richie AI chat): Full session-based chat — ChatService (7 API paths), session
  lifecycle (create on first send), optimistic UI, markdown, thinking-trace DisclosureGroup,
  memory-saved indicator, history sheet, suggestions/nudge empty state, typing indicator,
  per-session limit banner, monthly/rate-limit → paywall, save/unsave via context menu.

CURRENT STATE:
- App compiles and runs. Login, signup, and Richie chat all hit the real backend.
- HealthHub, Services, Profile tabs are stubs with placeholder content.

NEXT PHASE (Phase 3 — Health Hub tab):
- Android source: HealthDataFragment.java (~243KB). Has 6 side panels — each becomes a .sheet.
- Routes confirmed in ../richhealthbackend/routes/:
    medicalDataRoutes   → symptoms, measurements
    medicationRoutes    → medications (CRUD)
    symptomRoutes       → (check if separate or folded into medicalData)
    periodLogRoutes     → period tracking
    medicalReportRoutes → file upload + list
- Before coding: read each Android side panel + its backend controller to map edge cases.
- Charts via Swift Charts (AQI trend, report trends).
- File upload: .fileImporter / PhotosPicker + multipart URLSession.
- Edge cases to port: stale-data "data may not be current" warnings (age of measurements),
  sparse-data hints, neutral health-status defaults, pagination if lists are large.

HARD RULES (from CLAUDE.md — follow exactly):
- Check actual files before claiming behaviour. Confirm every endpoint against the controller.
- One canonical pattern per concept — GlassCard, .sheet drawer, .skeleton, StatusPill (§12).
- Edge-case parity: read Android source, list edge cases, port intent natively (§2A).
- No hardcoded colours in feature code — all colours from Theme.* or semantic SwiftUI
  colours (.primary, .secondary, .fill, materials). Zero Color(red:) outside Theme.swift (§14).
- Fan out with parallel Agent tool calls when researching 3+ independent backend routes (§15).
- StatusPill uses StatusLevel enum for status signals only (§12).
- Log every change in AI_CHANGE_LOG.md.
- Keep every .swift file compiling at all times.

OPEN DECISIONS (do not guess — ask before touching):
1. Pro payment method (blocks Phase 5 Paywall) — StoreKit 2 vs UPI deep-link vs web.
2. Final tab names/order (using Richie · Health Hub · Services · User for now).
```


## §27. StandardCard — the ONE canonical card/row (locked; verified by independent agents 2026-08-09)
Every card AND list row uses ONE component: `DesignSystem/Components/StandardCard.swift`. A list row is just `StandardCard(density: .row)` (see `HealthRecordRow`, a thin wrapper). Do NOT hand-roll a card/row layout — extend StandardCard.
- **Fixed slot map (positions never move by input):** icon/leadingView (leading 48 card / 44 row teal tile) · category (teal caps above title) · title · subtitle (short, directly under title) · status chip (**top-right, chip-only**) · body / bodyView (long text / structured content, full-width in the SAME left column as the title — never at the card edge) · date (**bare "X ago", bottom-right — NO divider, NO label prefix**) · chevron (trailing, vertically-centred).
- **Icon left, everything else in ONE content column** to its right — title, subtitle, body, and the meta date all share the same left edge. `subtitle` and `body`/`bodyView` are distinct slots; neither shifts based on what else is present.
- **Services dashboard cards are chevron-driven, NOT CTA-driven (2026-08-09 owner change).** On the Services dashboard there are NO per-card CTA buttons: the WHOLE card is the tap target via `onTap:`, and a trailing `chevron:` is the affordance. `ctaTitle`/`ctaAction`/`footerView` remain on the component ONLY for in-sheet cards (e.g. NutriCheck sheet); do not use them on the dashboard. Actions never sit in the top-right (that is chip-only).
- **Chevron = a status signal SEPARATE from the chip.** The chip labels the state; the chevron colour flags urgency/attention. `.urgent` = red (Urgent/Important, e.g. a critical health status), `.attention` = yellow (needs attention / stale — health data changed since this card was generated: `healthDataNeedsUpdate`, check-in due, NutriCheck/Dietary/Advisory `stale`), `.normal` = tertiary (plain "tap to open"). Both signals may appear on the same card. Purely informational, destination-less cards (AQI) may omit the chevron.
- **Date is a bare "X ago", bottom-right — NO divider, NO label prefix** (2026-08-09 owner change). Do not write "Last insight/Updated/Checked …" prefixes; the card title already gives the context. In-sheet cards that still use a CTA/footer keep CTA-left + date-right on one line. One `date:` slot — never hand-roll a timestamp elsewhere. (`.row` density keeps chip-over-date on the right.)
- **Apple Health card:** the heart-rate reading lives INSIDE the sheet, never on the card face. The face is icon · title · description · connected chip · last-sync date only.
- **No per-card font overrides for subtitle/body** — keep them uniform (`.subheadline`). `titleFont` may differ only for item cards (Briefing carousel, Feed row).
- **Exempt (owner decision, leave hand-rolled):** Services `WorkoutsCardView` and `DoctorSectionView` (multi-item with inline actions — kept exempt in the 2026-08-09 chevron pass too). Not yet migrated: Feed section header, StatChip/WatchStatChip/HubCard, in-sheet cards.
- When changing card look, change it ONLY in `StandardCard` — every screen updates. Verified end-to-end by two independent no-context audit agents on 2026-08-09.
- **Card spacing:** inner padding and the gap between cards both come from `Theme.Spacing.cardPadding` (20) — `GlassCard` uses it for inner padding (all cards app-wide), the Services card list uses it for the inter-card gap. Tune card breathing room ONLY there, so inner/outer stay consistent everywhere.
