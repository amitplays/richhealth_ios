# DESIGN SYSTEM — RichHealth iOS

> Source of truth for every visual decision in the app.
> Read alongside `CLAUDE.md` (§14 and §12) before touching any UI file.
> All tokens live in `DesignSystem/Theme.swift`. If something isn't here yet, add it there — never inline it.

---

## 1. Philosophy

The Android app's visual language is: **pure-black substrate + single teal accent + frosted white surfaces**. Every design decision flows from that.

iOS translation:
- **Black/near-black backgrounds** → SwiftUI adaptive backgrounds (`.background`, `.secondaryBackground`) which go near-black in dark mode and white in light mode. Do NOT hard-code `Color.black`.
- **Frosted white card surfaces** → `.ultraThinMaterial` (GlassCard). In iOS 26 this seamlessly upgrades to Liquid Glass.
- **Single teal accent** → `Theme.brandTeal` everywhere. No second chromatic accent.
- **4-state semantic status signals** → `StatusLevel` enum (§2). Nothing else for status.
- **Dark-first** — the app looks its best in dark mode. Light mode should be clean but is not the hero.

**Design keywords:** sparse, intentional, information-dense without clutter, teal-on-dark.

---

## 2. Color Tokens

### Brand color

| Swift token | Value | Usage |
|---|---|---|
| `Theme.brandTeal` | `Color(red: 0, green: 0.60, blue: 0.55)` ≈ `#00998C` | Buttons, icons, active states, pill accents, links |

Android reference: `#008B8B`. iOS intentionally slightly brighter — matches iOS brightness model better. Do not change without design approval.

### Adaptive semantic colors (use these — not named Color literals)

| SwiftUI token | Use case |
|---|---|
| `.primary` | Main body text |
| `.secondary` | Supporting text, subtitles, labels |
| `.tertiary` | Muted/inactive text, timestamps, meta |
| `.quaternary` | Hairline dividers |
| `.fill` | Background fill inside interactive elements |
| `.background` | Primary screen background |
| `.ultraThinMaterial` | Card / sheet surface |
| `.thinMaterial` | Bottom sheet background |
| `.regularMaterial` | Modal overlays |

> These automatically flip for dark/light mode and integrate with Liquid Glass. Never replace them with hardcoded Color hex.

### Status signal colors — via StatusLevel only

Status colors come exclusively through `StatusLevel.*.color`. See §12 of CLAUDE.md.

| `StatusLevel` | SwiftUI | Meaning |
|---|---|---|
| `.green` | `.green` | Healthy, good, active, verified |
| `.yellow` | `.yellow` | Borderline, pending, mild warning |
| `.orange` | `.orange` | Elevated, moderate concern |
| `.red` | `.red` | Critical, error, limit reached |

**Never write `.foregroundStyle(.green)` in feature code.** Use `.foregroundStyle(StatusLevel.green.color)`.

### What NOT to use in feature code

```swift
// FORBIDDEN in any file outside Theme.swift:
Color(red: 0.5, green: 0.3, blue: 0.7)
Color.red   /  .red
Color.green / .green
Color.blue  / .blue
Color.gray  / .gray
Color.white (as a surface)
Color.black (as a surface)
UIColor.*
```

---

## 3. Typography

Use SwiftUI's built-in type system. Do not hardcode font sizes.

| Use | SwiftUI modifier | Android equiv |
|---|---|---|
| Screen title | `.largeTitle.bold()` or `.title.bold()` | 28sp bold |
| Section heading | `.title2` or `.title3` | 22sp bold |
| Card title | `.headline` | 16sp bold |
| Body / primary row label | `.body` | 15sp |
| Secondary row text | `.subheadline` | 14sp |
| Supporting / description | `.footnote` | 13sp |
| Caption / timestamp / meta | `.caption` | 12sp |
| Pill / badge / micro-label | `.caption2.weight(.semibold)` | 11sp bold |

**Weight modifiers:** `.weight(.semibold)` for emphasis, `.weight(.bold)` for titles only. Avoid `.weight(.heavy)`.

**Color:** Always `.primary`, `.secondary`, `.tertiary` — never hardcoded white/gray values.

---

## 4. Spacing

All spacing comes from `Theme.Spacing`. No magic numbers in layout code.

| Token | Value | Use |
|---|---|---|
| `Theme.Spacing.xs` | 4 pt | Tight internal gaps (icon-to-text, pill padding) |
| `Theme.Spacing.s` | 8 pt | Small gaps between related elements |
| `Theme.Spacing.m` | 16 pt | Standard card padding, screen horizontal margins |
| `Theme.Spacing.l` | 24 pt | Section spacing, larger gaps |
| `Theme.Spacing.xl` | 32 pt | Hero sections, large top/bottom breathing room |

**Android reference:** `rh_screen_margin=16dp`, `rh_card_gap=18dp`, `rh_card_padding=16dp`, `rh_row_v_padding=15dp`

---

## 5. Corner Radii

All radii come from `Theme.CornerRadius`. Never write a raw `cornerRadius(20)`.

| Token | Value | Used for |
|---|---|---|
| `Theme.CornerRadius.card` | 20 pt | GlassCard, content cards |
| `Theme.CornerRadius.button` | 12 pt | Filled action buttons |
| `Theme.CornerRadius.sheet` | 22 pt | Bottom sheet top corners |
| `Theme.CornerRadius.icon` | 14 pt | Icon container backgrounds |
| `Theme.CornerRadius.input` | 12 pt | Text fields, search bars |

Pills / status badges use `.capsule()` shape — NOT a fixed radius.

**Android reference:** card=18dp, dialog=22dp, sheet=22dp, pill=999dp (capsule).

---

## 6. Icon Sizing

Use the standard SF Symbols sizing, not hardcoded frames.

| Context | Frame | Android equiv |
|---|---|---|
| Navigation / tab bar | `.font(.body)` (system manages) | `icon_nav = 20dp` |
| Inline in rows (secondary) | `.font(.body)` | `icon_sm = 20dp` |
| Card primary icon | `.font(.title2)` | `icon_lg = 28–30dp` |
| Hero / prominent button icon | `.font(.title)` | `icon_xl = 36dp` |
| Touch target (tappable icon) | `.frame(width: 44, height: 44)` | `container_md = 48dp` |
| Avatar / profile circle | `.frame(width: 44, height: 44)` | `container_lg = 56dp` |

---

## 7. Component Catalog

### GlassCard

**File:** `DesignSystem/Components/GlassCard.swift`

```swift
GlassCard {
    // content
}
```

- Surface: `.ultraThinMaterial` — adaptive, integrates with Liquid Glass in iOS 26
- Corner radius: `Theme.CornerRadius.card` (20 pt)
- Padding: `Theme.Spacing.m` (16 pt) on all sides
- Elevation: none (matches Android's flat card philosophy)
- **Always use GlassCard for cards.** Never hand-roll a VStack with a background for a card-shaped element.

### StatusPill

**File:** `DesignSystem/Components/StatusPill.swift`

```swift
StatusPill(text: "Healthy", level: .green)      // status signal
StatusPill(text: "Pro")                          // plan badge (brand teal)
StatusPill(text: "Custom", tint: Theme.brandTeal) // custom tint
```

- Typography: `.caption2.weight(.semibold)`
- Shape: `.capsule()`
- Padding: 10 horizontal, 4 vertical
- Background: tint at 15% opacity; text at 100% tint
- **Use `level:` only for the 4 StatusLevel states.** Plan/feature badges omit `level`.

### UsageRing

**File:** `DesignSystem/Components/UsageRing.swift`

```swift
UsageRing(value: 0.6)           // 60% usage
UsageRing(value: 0.9, label: "9/10")
```

- Native SwiftUI `Gauge` with `.accessoryCircularCapacity` style
- Tint: `Theme.brandTeal`
- Replaces Android's `UsageRing` custom drawable

### Skeleton loading

**File:** `DesignSystem/Components/SkeletonModifier.swift`

```swift
Text("Placeholder text that matches real content length")
    .skeleton(isActive: viewModel.isLoading)
```

- Use `.redacted(reason: .placeholder)` shimmer
- Always provide realistic placeholder content (same length as real data) so layout doesn't shift
- Use `FeedItem.placeholder`, `MedicalDataRecord.placeholder`, etc. (defined in Models) for list skeletons

---

## 8. Layout Patterns

### Screen scaffold

```swift
NavigationStack {
    ScrollView {
        LazyVStack(spacing: Theme.Spacing.m) {
            // cards
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
    }
    .navigationTitle("Screen Title")
    .refreshable { await vm.reload() }
}
.task { await vm.load() }
```

### Card internal layout (standard row)

Android's canonical card has: `[icon 28dp] [title + subtitle] [chevron]`. iOS equivalent:

```swift
GlassCard {
    HStack(spacing: Theme.Spacing.s) {
        Image(systemName: "heart.fill")
            .font(.title2)
            .foregroundStyle(Theme.brandTeal)
            .frame(width: 44, height: 44)
        
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.headline)
            Text("Subtitle / description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        
        Spacer()
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
```

### Section headers

Android uses 11sp ALL-CAPS, letter-spaced, gray section labels. iOS equivalent:

```swift
Text("SECTION TITLE")
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
    .textCase(.uppercase)
    .tracking(1.2)
    .padding(.horizontal, 4)
```

### Empty state

Always use `ContentUnavailableView`. Never show a blank screen.

```swift
ContentUnavailableView(
    "No Data Yet",
    systemImage: "heart.text.square",
    description: Text("Add some data to see it here.")
)
```

### Bottom sheets

```swift
.sheet(item: $vm.activeSheet) { sheet in ... }
.presentationDetents([.medium, .large])     // most sheets
.presentationDetents([.large])              // form/content-heavy sheets
.presentationDragIndicator(.visible)
.presentationBackground(.thinMaterial)
```

### Inline icon badge (avatar initials)

```swift
ZStack {
    Circle()
        .fill(Theme.brandTeal.opacity(0.15))
        .frame(width: 44, height: 44)
    Text(name.prefix(2).uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.brandTeal)
}
```

### Confirmation before destructive action

```swift
.confirmationDialog("Delete this item?", isPresented: $vm.showDeleteConfirm) {
    Button("Delete", role: .destructive) { vm.delete() }
    Button("Cancel", role: .cancel) { }
}
```

---

## 9. Android → iOS Reference Map

| Android element | iOS native replacement |
|---|---|
| `MaterialCardView` 18dp corner | `GlassCard` (`.ultraThinMaterial`, 20pt radius) |
| Bottom nav `BottomNavigationView` | `TabView` (iOS 26: Liquid Glass floating pill, automatic) |
| Side panels (`layout_*_panel.xml`) | `.sheet` with `.presentationDetents` |
| Custom dialogs (`DialogUtils.java`) | `.alert` (yes/no) or `.sheet` (form) |
| `RecyclerView` with items | `List` or `LazyVStack` in `ScrollView` |
| `ChipGroup` | `HStack` with `ForEach` + `StatusPill` or `Button(.bordered)` |
| `StatusPill.java` (Utils) | `StatusPill(text:level:)` component |
| `Skeleton.java` | `.skeleton(isActive:)` modifier |
| `UsageRing.java` | `UsageRing(value:)` component |
| `TextFormatter.java` markdown | `Text(try! AttributedString(markdown: str))` |
| `BiometricHelper.java` | `LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics…)` |
| Swift Charts | Android custom chart views |
| `CLLocationUpdate.liveUpdates()` | Android `FusedLocationProviderClient` |
| `MKReverseGeocodingRequest` | Android `Geocoder.getFromLocation()` |
| Plan badge pill | `StatusPill(text: "Pro")` (no level = brand teal) |
| `SeekBar` for severity/intensity | SwiftUI `Slider(value:in:step:)` |
| `SwitchMaterial` | `Toggle` |
| Pagination in RecyclerView | `.onAppear` on last item → `loadMore()` |
| File picker | `.fileImporter` |
| Photo picker | `PhotosPicker` |

---

## 10. Android Design Values for Reference

These are what the Android app uses. iOS uses the adaptive equivalents above — this table is for design intent alignment.

| Android token | Value | iOS semantic |
|---|---|---|
| `rh_bg` | `#000000` | `.background` (near-black in dark mode) |
| `rh_surface` | `#0CFFFFFF` (5% white on black) | `.ultraThinMaterial` |
| `rh_surface_elevated` | `#262626` | `.thinMaterial` |
| `rh_accent` | `#008B8B` | `Theme.brandTeal` |
| `rh_text_primary` | `#FFFFFF` | `.primary` |
| `rh_text_secondary` | `#CCCCCC` | `.secondary` |
| `rh_text_tertiary` | `#808080` | `.tertiary` |
| `rh_text_label` | `#8A8E96` | `.secondary` |
| `rh_divider` | `#262626` | `Divider()` (system managed) |
| `rh_danger` | `#FF5252` | `StatusLevel.red.color` |
| `rh_success` | `#4CAF50` | `StatusLevel.green.color` |
| `rh_warning` | `#FFC107` | `StatusLevel.yellow.color` |
| Card corner | `18dp` | `Theme.CornerRadius.card` (20pt) |
| Screen margin | `16dp` | `Theme.Spacing.m` |
| Card gap | `18dp` | `Theme.Spacing.m` |
| Card padding | `16dp` | `Theme.Spacing.m` |
| Row v-padding | `11–15dp` | `Theme.Spacing.s` – `Theme.Spacing.m` |

---

## 11. Anti-patterns (things we have seen go wrong)

| Anti-pattern | Correct replacement |
|---|---|
| `.foregroundStyle(.green)` in feature code | `.foregroundStyle(StatusLevel.green.color)` |
| `.foregroundStyle(.red)` for destructive button | Acceptable for destructive action affordance — but add a comment explaining why |
| `Color(red:green:blue:)` outside Theme.swift | Add to `Theme.swift`, name it, use `Theme.thatColor` |
| `VStack { ... }.background(.white).cornerRadius(16)` | `GlassCard { ... }` |
| `.padding(12)` (magic number) | `.padding(Theme.Spacing.s)` or `.padding(Theme.Spacing.m)` |
| `.cornerRadius(18)` (magic number) | `.clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card))` |
| Two completely different card designs on the same screen | One `GlassCard` style everywhere |
| Multiple `.skeleton` implementations per file | Single `.skeleton(isActive:)` from `SkeletonModifier` |
| Fetching data again on every tab switch | `.task` once; only refetch on explicit user action |
| Generic error toast for 429 | Route `APIError.limitReached` → `PaywallView` |

---

## 12. Verification checklist (before opening a PR)

```bash
# Should have ZERO hits in richhealth/ (feature code), except Theme.swift:
grep -r "Color(red:" richhealth/richhealth/
grep -r "Color(#" richhealth/richhealth/
grep -r "\.foregroundStyle(.red)" richhealth/richhealth/Features/
grep -r "\.foregroundStyle(.green)" richhealth/richhealth/Features/
grep -r "\.foregroundStyle(.orange)" richhealth/richhealth/Features/
grep -r "cornerRadius([0-9]" richhealth/richhealth/Features/
grep -r "\.padding([0-9]" richhealth/richhealth/Features/
grep -r "\.spacing([0-9]" richhealth/richhealth/Features/
```
