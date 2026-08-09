import SwiftUI

/// THE canonical card/row for the whole app (§2A — one pattern per concept).
///
/// FIXED layout — the icon sits top-left; EVERYTHING else lives in one content column to its
/// right, so title, subtitle, body, warning, the divider and the meta row all share the SAME
/// left edge. Nothing shifts based on which values are supplied.
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ [icon]  CATEGORY (teal caps)           [chip] │  header
/// │         Title                                 │
/// │         Subtitle (short)                      │
/// │         Body (long text)                      │  body
/// │         ⚠ Warning banner                      │
/// │         ─────────────────────────────         │  divider (only when a meta row exists)
/// │         CTA / footer            date          │  meta
/// └──────────────────────────────────────────────┘
/// ```
///
/// Slots & their ONE reserved position:
/// - icon / leadingView — leading (48 card / 44 row teal tile, or a same-sized image/avatar)
/// - category — teal caps above the title
/// - title — top of the content column
/// - subtitle — directly under the title (short)
/// - body — under the subtitle (long text) — SAME left edge as everything else
/// - warning — orange banner
/// - CTA (`ctaTitle`) — bottom-left, always teal `.subheadline.semibold` (one CTA style everywhere)
/// - footer (`footerView`) — bottom-left alternative to the CTA for bespoke content (metric, chart, progress)
/// - date — bottom-right
/// - a Divider always separates the meta row from the content above it, on every card that has one.
///
/// Density unifies lists and cards with the same slots:
/// - `.card` → wrapped in `GlassCard` (Services / detail cards).
/// - `.row`  → no wrapper, compact list row (chip over date on the right). `HealthRecordRow` uses this.
struct StandardCard: View {

    enum Density { case card, row }

    var density: Density = .card
    /// Row-only tighter variant (e.g. Apple Watch imports): smaller icon + tighter height.
    var compact: Bool = false

    // Leading
    var icon: String? = nil
    /// Custom leading view (image / avatar). Overrides `icon`; sized to the same leading frame.
    var leadingView: AnyView? = nil

    // Header
    var category: String? = nil
    var title: String
    var titleFont: Font? = nil
    var titleColor: Color = .primary
    var titleLineLimit: Int? = nil
    var subtitle: String? = nil
    var subtitleFont: Font = .subheadline
    var subtitleColor: Color = .secondary
    var subtitleLineLimit: Int? = 2

    // Header trailing
    var statusText: String? = nil
    var statusLevel: StatusLevel? = nil

    // Body
    var bodyText: String? = nil
    var bodyFont: Font = .subheadline
    var bodyColor: Color = .secondary
    var bodyLineLimit: Int? = nil
    /// Structured full-width body content (charts, metric rows, bullet lists). Sits under
    /// `bodyText`, in the SAME left-aligned column — never in the meta/footer slot.
    var bodyView: AnyView? = nil
    var warning: String? = nil

    // Meta row (bottom)
    /// Canonical text CTA, rendered bottom-left in the one consistent style. Prefer this over
    /// `footerView` for "View …/Read more" style actions so every CTA looks identical.
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil
    /// Bespoke bottom-left content when the meta slot isn't a plain CTA (metric, chart, progress).
    var footerView: AnyView? = nil
    /// Bottom-right timestamp.
    var date: String? = nil

    var body: some View {
        switch density {
        case .card:
            GlassCard { cardContent }
        case .row:
            rowContent.padding(.vertical, compact ? 3 : Theme.Spacing.s)
        }
    }

    // MARK: - Card layout (single content column right of the icon)

    private var cardContent: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            leadingSlot
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 3) {
                        categoryLabel
                        titleLabel
                        subtitleLabel
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    statusChip
                }
                bodyLabel
                if let bodyView {
                    bodyView.frame(maxWidth: .infinity, alignment: .leading)
                }
                warningLabel
                metaRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // §18 stretch to width
        }
    }

    // Divider + (CTA/footer left, date right). Only when there's something to show.
    @ViewBuilder private var metaRow: some View {
        if hasMeta {
            Divider()
            HStack {
                if let ctaTitle, !ctaTitle.isEmpty {
                    Button(ctaTitle) { ctaAction?() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brandTeal)
                        .buttonStyle(.plain)
                } else if let footerView {
                    footerView
                }
                Spacer(minLength: Theme.Spacing.s)
                dateLabel
            }
        }
    }

    private var hasMeta: Bool {
        (ctaTitle?.isEmpty == false) || footerView != nil || (date?.isEmpty == false)
    }

    // MARK: - Row layout (compact list row: chip over date on the right)

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.m) {
            leadingSlot
            VStack(alignment: .leading, spacing: 3) {
                titleLabel
                subtitleLabel
            }
            if statusText != nil || (date?.isEmpty == false) {
                Spacer(minLength: Theme.Spacing.s)
                if compact {
                    HStack(spacing: Theme.Spacing.s) { statusChip; dateLabel }
                } else {
                    VStack(alignment: .trailing, spacing: 4) { statusChip; dateLabel }
                }
            }
        }
    }

    // MARK: - Slot views

    @ViewBuilder private var leadingSlot: some View {
        if let leadingView {
            leadingView.frame(width: leadingSize, height: leadingSize)
        } else if let icon {
            iconTile(icon)
        }
    }

    @ViewBuilder private var categoryLabel: some View {
        if let category, !category.isEmpty {
            Text(category.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.brandTeal)
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(resolvedTitleFont)
            .foregroundStyle(titleColor)
            .lineLimit(titleLineLimit ?? (density == .row ? 1 : nil))
    }

    @ViewBuilder private var subtitleLabel: some View {
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(subtitleColor)
                .lineLimit(subtitleLineLimit)
        }
    }

    @ViewBuilder private var bodyLabel: some View {
        if let bodyText, !bodyText.isEmpty {
            Text(bodyText)
                .font(bodyFont)
                .foregroundStyle(bodyColor)
                .lineLimit(bodyLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var warningLabel: some View {
        if let warning, !warning.isEmpty {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(StatusLevel.orange.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var statusChip: some View {
        if let statusText, !statusText.isEmpty {
            if let statusLevel {
                StatusPill(text: statusText, level: statusLevel)
            } else {
                StatusPill(text: statusText)
            }
        }
    }

    @ViewBuilder private var dateLabel: some View {
        if let date, !date.isEmpty {
            Text(date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var resolvedTitleFont: Font {
        if let titleFont { return titleFont }
        if density == .row && compact { return .subheadline.weight(.medium) }
        return .headline
    }

    private var leadingSize: CGFloat { density == .card ? 48 : (compact ? 34 : 44) }

    private func iconTile(_ name: String) -> some View {
        let glyph: CGFloat = density == .card ? 22 : (compact ? 16 : 20)
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.icon)
                .fill(Theme.brandTeal.opacity(0.12))
                .frame(width: leadingSize, height: leadingSize)
            Image(systemName: name)
                .font(.system(size: glyph, weight: .medium))
                .foregroundStyle(Theme.brandTeal)
        }
    }
}
