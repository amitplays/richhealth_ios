# UI_AUDIT.md — Android → iOS Layout Fidelity Audit

> Run after every completed phase. Records gaps between Android XML layouts and the iOS implementation.
> **Status key:** ✅ Fixed | ⚠️ Intentional iOS pattern (not a gap) | ❌ Outstanding

---

## Audit 1 — 2026-08-07 (Post Phase 5)

Parallel agents read all Android XML layouts and grepped for hardcoded colors across the iOS codebase.
Sources audited: `activity_login.xml`, `activity_signup.xml`, `fragment_ai.xml`, `fragment_health_data.xml`, `fragment_home.xml`, `fragment_profile.xml`, plus chat/item layouts.

---

### Auth screens

#### LoginView

| Android | iOS before | iOS after | Status |
|---|---|---|---|
| Logo + "RichHealth" teal 32sp bold | Logo + teal name + tagline | Same + tagline | ✅ |
| MaterialCardView `#1A1A1A` wrapping form | GlassCard (`.ultraThinMaterial`) | GlassCard kept | ⚠️ iOS material equivalent |
| `#262626` bg + teal stroke input fields | `brandedInputStyle()` | Same | ✅ |
| "Forgot password?" teal, right-aligned | **MISSING** | Added between password and login button | ✅ |
| 56dp full-width teal login button | `.borderedProminent` tint teal | Same | ✅ |
| ProgressView spinner on loading | `.tint(.white)` (no annotation) | Added `// contrast on teal button` | ✅ |

#### SignupView

| Android | iOS before | iOS after | Status |
|---|---|---|---|
| Dark MaterialCardView wrapping all step fields | SwiftUI `Form` (plain list rows) | GlassCard + `brandedInputStyle()` per field | ✅ |
| 80x80dp circular icon card per step | Circle with `brandTeal.opacity(0.12)` | Same — teal circle is close enough to Android's `#1A1A1A` icon circle in context | ⚠️ Intentional |
| 4 orange/teal active, gray inactive step bars | Capsule-filled step bars | Same | ✅ |
| Steppers / Spinners for height/weight | SwiftUI `Form` `Stepper` | Branded HStack row with `Stepper.labelsHidden()` | ✅ |
| Dropdown Spinners for gender/goal/diet | `.segmented` / `.menu` Picker inside Form | Gender: `.segmented`; Goal/Activity/Diet: `.menu` inside branded HStack | ✅ |
| DatePicker (no graphical calendar on signup) | `.graphical` DatePicker | `.compact` style in branded HStack | ✅ |
| OTP step — simple code entry form | SwiftUI `Form` | Form kept (simple, correct) | ✅ |

---

### Chat / Richie tab

| Android | iOS | Status |
|---|---|---|
| User bubble: solid `#008b8b` teal, white text, radius 16dp | `Theme.brandTeal` bg + `.foregroundStyle(.white)` | `.white` annotated `// white text on teal for contrast` | ✅ |
| AI bubble: `#AD3E3C3C` dark translucent, white text | `.ultraThinMaterial` GlassCard equivalent | ⚠️ iOS material is correct native equivalent |
| Input bar: `#111111` bg, teal stroke, radius 22dp | `brandedInputStyle()` on search bar | ✅ |
| "Thinking" collapsible disclosure | `DisclosureGroup` | ✅ |
| Animated sparkle logo (slow/fast) | `sparkles` icon + `@State` rotation animation | ✅ |

---

### Health Hub tab

| Android | iOS | Status |
|---|---|---|
| Cards: `#0CFFFFFF` (white ~7%), radius 18dp, teal stroke 0.5dp | `GlassCard` with `.ultraThinMaterial` | ⚠️ iOS material is the correct adaptive equivalent |
| 48x48dp teal icon containers per card | `Theme.IconSize.card` frame with `.fill` background | ✅ |
| Section labels: `"DAILY TRACKING"`, uppercase, `#666666` 11sp bold | `.caption.weight(.semibold)` `.foregroundStyle(.tertiary)` | ✅ |
| Six side panels → six native sheets | Six `.sheet` with `.presentationBackground(.thinMaterial)` | ✅ |
| StatusPill with `.green/.yellow/.orange/.red` | `StatusLevel` enum routed through `StatusPill` | ✅ |
| Status color functions in MeasurementsSheetView | Returns `StatusLevel` (was already correct) | ✅ |
| Status color functions in PeriodLogSheetView | Returns `StatusLevel` (was already correct) | ✅ |

---

### Services tab

| Android | iOS | Status |
|---|---|---|
| Feed tab chips: selected = teal bg, white text | `Theme.brandTeal` chip + `.white` text | `.white` annotated `// white: contrast on teal chip` | ✅ |
| AQI card with status pill | `StatusLevel` mapping | ✅ |
| NutriCheck error message `.red` | Unannotated | Added `// error feedback` | ✅ |
| NutriCheck submit button ProgressView `.white` | Unannotated | Added `// contrast on teal button` | ✅ |
| NutriCheck thumbsdown `.red` | Unannotated | Added `// negative reaction indicator` | ✅ |
| Workout error message `.red` | Unannotated | Added `// error feedback` | ✅ |
| Doctor search/action errors `.red` (×2) | Unannotated | Added `// error feedback` ×2 | ✅ |

---

### Profile tab

| Android | iOS | Status |
|---|---|---|
| Pill tabs (3 LinearLayouts in rounded container) | `.segmented` Picker | ⚠️ iOS `.segmented` is the native equivalent; Liquid Glass renders well |
| 58x58dp avatar circle + edit/logout icon buttons | 72pt initials circle + edit/logout in header | ✅ |
| Logout `.tint(.red)` | Already annotated `// error feedback — destructive action` | ✅ |
| Edit sheet `.foregroundStyle(.red)` | Already annotated `// error feedback` | ✅ |

---

## Hardcoded color audit — full grep results

All `.red` / `.white` / `.orange` / `.green` / `.yellow` in feature code are now either:
1. Annotated `// error feedback` (destructive action or error message)
2. Annotated `// contrast on teal button/chip` (white text on teal background)
3. Annotated `// negative reaction indicator` (thumbsdown)
4. Routing through `StatusLevel.*.color` (health status signals)
5. Using `Theme.brandTeal` / SwiftUI semantic colors

**Zero raw `Color(red:green:blue:)` calls outside `Theme.swift`.**

---

## Outstanding items (not yet fixed)

| Item | Why deferred |
|---|---|
| Profile pill tabs (Android custom tabs) | iOS `.segmented` is acceptable native; custom pill would require extra complexity |
| Payment method (PaywallView upgrade button) | Open decision §10 — StoreKit 2 vs web |
| Signup OTP step — card layout | OTP is a minimal 2-field form; Form is correct here |

---

## Post-phase audit process

After every completed phase, spawn parallel Explore agents:
1. One per major Android XML layout (activity/fragment)
2. One grep agent for `Color\.` / `\.red` / `\.green` / `\.orange` / `\.yellow` / `\.white`
3. Compare findings against current iOS files
4. Update this document with new rows

