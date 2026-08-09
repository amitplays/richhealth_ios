# NATIVE_COMPONENTS.md — Android → iOS native mapping

> Companion to **CLAUDE.md**. For every Android UI surface, this is the native iOS control to use and why.
> Rule: **native first.** Only build custom when there is genuinely no native equivalent, and record that decision here.
> Android references are read-only (`../richhealth_android`). The point is behaviour parity, not visual copying.

Legend for "Gap": ✅ direct native equivalent · 🔶 closest native pattern (small rethink) · ⛔ no equivalent / needs a decision.

**Consistency law (from CLAUDE.md §2A):** pick **one** native control per concept and use it everywhere — one card (`GlassCard`), one drawer (`.sheet`), one picker pattern, one skeleton, one overflow-CTA (`Menu`/ellipsis). Reuse the shared component before writing a new one. Handle the **same edge cases** the Android screen handled.

---

## 1. Navigation & app shell

| Android | iOS native | Gap | Notes |
|---|---|---|---|
| `BottomNavigationView` + `res/menu/bottom_navigation_menu.xml` (4 tabs: Richie · Health Hub · Services · User) | **`TabView`** with `Tab { } label:` | ✅ | On iOS 26 the tab bar renders as the **Liquid Glass floating pill** automatically. Do **not** hand-roll a pill. Keep to 4–5 tabs. |
| `MainActivity` fragment host + manual `setSelectedItemId` | `TabView(selection:)` + a `Router` per tab | ✅ | Each tab owns a `NavigationStack(path:)`. |
| `SplashActivity` + `activity_splash.xml` (does token check, routing) | Static **LaunchScreen** (no logic) + a root `.task` that checks Keychain token | 🔶 | iOS launch screens cannot run code. Do the token/route decision in `RootView`, not the splash. |
| `onBackPressed` chain, `BackPressHandler`, "press back again to exit" toast | `NavigationStack` + interactive swipe-back; sheet drag-to-dismiss | ⛔→drop | iOS has **no hardware back and no back-to-exit**. Delete the whole back-handling model; it's meaningless on iOS. |
| Fragment `ViewPager` tabs (check-in current/history, nutri-check check/history, dietary list/history, doctor find/connected/pending) | **`Picker(.segmented)`** driving a switch, or `TabView(.page)` for swipeable | ✅ | Use segmented control for labelled sub-tabs; page style only where swiping is expected. |

---

## 2. Side panels → sheets (the biggest rethink)

Android uses slide-in **side panels** (an anti-pattern on iOS). Every one becomes a **bottom sheet** with detents, or a `NavigationStack` push if it's really a full screen. Owner's guidance: *bottom drawers are more native than side panels.*

| Android side panel (layout) | Used in | iOS native | Gap |
|---|---|---|---|
| `layout_side_panel.xml`, `layout_chat_side_panel.xml`, `layout_saved_chats_panel.xml` | `AIFragment` (Richie) | `.sheet` + `.presentationDetents([.medium, .large])` | 🔶 |
| `layout_symptoms_panel.xml` | HealthDataFragment | `.sheet` (medium) | 🔶 |
| `layout_measurements_panel.xml` | HealthDataFragment | `.sheet` | 🔶 |
| `layout_medications_panel.xml` | HealthDataFragment | `.sheet` | 🔶 |
| `layout_medical_reports_panel.xml` | HealthDataFragment | `.sheet` (+ `.fileImporter`/`PhotosPicker` for upload) | 🔶 |
| `layout_period_logs_panel.xml` | HealthDataFragment | `.sheet` | 🔶 |
| `layout_family_members_panel.xml` | HealthDataFragment | `.sheet` or pushed screen | 🔶 |

Pattern: one `@State var activeSheet: HealthHubSheet?` (enum) per host screen, `.sheet(item:)` to present. Use `.presentationDetents`, `.presentationDragIndicator(.visible)`, and `.presentationBackground(.thinMaterial)` for the glass look.

---

## 3. Dialogs → native alerts / confirmation dialogs / sheets

Android hand-builds dialogs via `DialogUtils.java` (53KB), `FoodDialogUtils.java`, `CardInfoDialog`, `ProUpgradeDialog` (79KB), plus ~40 `dialog_*.xml`. Native rule: **decision → alert; choice list → confirmationDialog; form/rich content → sheet.**

| Android dialog | iOS native | Gap |
|---|---|---|
| Confirm / discard / error / "are you sure" (`DialogUtils` yes-no) | **`.alert`** | ✅ |
| Action choice list (e.g. report type, pick source) `dialog_report_type`, `dialog_field_picker` | **`.confirmationDialog`** or `Menu`/`Picker` | ✅ |
| Field input dialogs `dialog_field_input`, `dialog_field_multiline`, `dialog_other_input`, `OtherInputDialog` | `.alert` with `TextField` (single) or `.sheet` with a `Form` (multi) | 🔶 |
| Multi-select `dialog_field_multiselect` | `.sheet` with a `List` + multi-selection | 🔶 |
| Add/edit forms `dialog_add_medication`, `dialog_add_symptom`, `dialog_add_measurement`, `dialog_add_period_log`, `dialog_edit_profile`, `dialog_add_family_member`, `add_workout`/`dialog_edit_workout` | **`.sheet`** with a `Form` + `NavigationStack` toolbar (Cancel/Save) | ✅ |
| Rich info cards `dialog_card_info`, `CardInfoDialog`, `dialog_food_info`, `FoodDialogUtils`, `dialog_feed_why` | `.sheet` (medium detent) | ✅ |
| Charts `dialog_aqi_chart`, `dialog_report_trend_chart` | `.sheet` containing **Swift Charts** | ✅ |
| Usage / limit `dialog_usage_status`, `sheet_usage_status`, `UsageBottomSheet`, `layout_chat_limit_dialog` | `.sheet` with detents | ✅ |
| Pro upgrade `dialog_pro_upgrade`, `ProUpgradeDialog`, `dialog_pro_management` | **`PaywallView` in a `.sheet`** (payment mechanism = open decision, CLAUDE.md §10) | ⛔ payment |
| Biometric setup `dialog_biometric_setup` | **LocalAuthentication** system prompt (no custom UI) | ✅ |
| Terms `dialog_terms_and_conditions`, `TermsAndConditionsDialog` | `.sheet` with scrollable text + accept button | ✅ |
| Payment result `dialog_payment_success`, `dialog_payment_failed` | Result state inside the paywall sheet, or `.alert` | ✅ |
| Checkin questions `dialog_checkin_questions` | pushed screen or `.sheet` form | ✅ |

Delete `DialogUtils`-style central dialog factories; SwiftUI modifiers replace them per-view.

---

## 4. Lists, cards & feed

| Android | iOS native | Gap |
|---|---|---|
| `RecyclerView` + `*Adapter.java` (ChatAdapter, WorkoutAdapter, MedicalDataAdapter, Feed, Podcast, etc.) | **`List`** or `ScrollView`+`LazyVStack` with `ForEach` | ✅ Adapters disappear — data binds directly. |
| `item_*.xml` row layouts | SwiftUI row `View`s | ✅ |
| CardView (`item_feed_card`, `item_health_card`, `BriefingCard`) | `GlassCard` wrapper (`.glassEffect`) or grouped `List` sections | ✅ |
| Swipe actions (if any) | `.swipeActions` | ✅ |
| Section headers `item_section_header` | `Section { } header:` | ✅ |
| Pull to refresh | `.refreshable` | ✅ |

---

## 5. Inputs & controls

| Android | iOS native | Gap |
|---|---|---|
| `TextInputLayout` / `EditText` | `TextField` / `SecureField` (`.textFieldStyle`, `.textContentType`, `.keyboardType`) | ✅ |
| `Spinner` / dropdown (`dropdown_item`, `spinner_dropdown_item`) | `Picker` (menu/wheel) or `Menu` | ✅ |
| Chips (`chip_background`) | ⛔ no native chip → wrapping row of `Capsule` toggle buttons (small custom component) | 🔶 |
| `MaterialButton` (filled/outline) | `Button` + `.buttonStyle(.borderedProminent)` / `.glass` / `.bordered` | ✅ |
| Switch / checkbox | `Toggle` | ✅ |
| Slider (activity/stress levels) | `Slider` | ✅ |
| Date pickers | `DatePicker` | ✅ |
| Segmented sub-tabs | `Picker(.segmented)` | ✅ |
| Selectable cards (`SelectableCardAdapter`, onboarding option cards) | `ForEach` of tappable cards with selection state | ✅ |

---

## 6. Custom widgets (Android Utils) → iOS

| Android widget | iOS native | Gap |
|---|---|---|
| `StatusPill.java`, `PlanBadge.java` | `StatusPill` = `Capsule` + `Text` (DesignSystem/Components) | 🔶 tiny custom |
| `UsageRing.java` | **`Gauge(value:) .gaugeStyle(.accessoryCircularCapacity)`** or custom `Circle().trim` | ✅ |
| `Skeleton.java` | `.redacted(reason: .placeholder)` + shimmer overlay | ✅ |
| `SimpleProgress.java`, `progress_ring` | `ProgressView()` / `ProgressView(value:)` | ✅ |
| `AnimatedActionButton.java`, `IconAnimator.java` | SwiftUI `.animation`, `.symbolEffect`, `withAnimation` | ✅ |
| `TextFormatter.java`, `MarkdownChunker.java` (chat markdown) | `AttributedString(markdown:)` / `Text(attributed)` | ✅ |
| `NutriCheckFeedback`, `HealthLogParser` | plain Swift model/formatter code | ✅ |

---

## 7. System integrations

| Android | iOS native framework | Gap |
|---|---|---|
| `BiometricHelper.java` (BiometricPrompt) | **LocalAuthentication** (`LAContext`, Face ID/Touch ID) | ✅ |
| `CheckInNotificationHelper`, `createNotificationChannel`, `CheckInNotificationReceiver` | **`UNUserNotificationCenter`** (local) / APNs (push). No "channels" on iOS. | 🔶 |
| `ContactUtils.java` (contact access) | **Contacts / ContactsUI** (`CNContactPickerViewController`) | ✅ |
| AQI location (`ACCESS_FINE_LOCATION`) | **CoreLocation** (`CLLocationManager`, request when-in-use) | ✅ |
| Medical report upload (multipart) | `PhotosPicker` / `.fileImporter` + multipart `URLSession` | ✅ |
| Image loading (feed/podcast art) | **`AsyncImage`** (or a tiny cache actor) | ✅ |
| Toast / Snackbar | ⛔ no native toast → transient SwiftUI overlay or `.alert`; prefer inline state | 🔶 Use sparingly; often just remove. |
| Podcast audio (`*.mp3` in raw, PodcastAdapter) | **AVFoundation** (`AVPlayer`) — only if the feature ships (Android's podcast flow is dead code) | 🔶 confirm feature is wanted |
| UPI payment intents (Paytm/Razorpay external apps) | ⛔ **no UPI on iOS.** StoreKit 2 (IAP) is the compliant path for digital Pro; or web checkout. **Decision — CLAUDE.md §10.** | ⛔ |
| Local SQLite (`DatabaseHelper.java`) | ⛔ **not migrated** — stateless client, Keychain for token only (CLAUDE.md §1.3) | n/a |

---

## 8. Liquid Glass usage notes

- The **TabView** bottom bar and standard navigation bars get Liquid Glass for free on iOS 26 — don't override their materials.
- For custom floating surfaces (cards, the paywall header, chat input bar), use **`.glassEffect(in:)`** / `GlassEffectContainer` rather than faking blur with opacity.
- Sheets: `.presentationBackground(.thinMaterial)` + drag indicator for the drawer feel.
- Respect the **Dynamic Island / safe areas** — never place tappable content under it; use `.safeAreaPadding`. Consider a **Live Activity** for long-running things (report processing, daily check-in reminders) in a later phase.
- Keep tint consistent with the brand teal (see `DesignSystem/Theme.swift`).

---

## 9. Decisions still open (mirror of CLAUDE.md §10)

1. **Pro payment on iOS** — StoreKit 2 vs UPI deep-link vs web. ⛔ needs owner + backend endpoints. Blocks the Paywall.
2. **Final tab names/order** — menu XML vs the older report disagree.
3. **Podcast feature** — dead code in Android; confirm before building `AVPlayer` UI.
4. **Notifications scope** — local reminders only, or push (needs APNs + backend)?
