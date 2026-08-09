import SwiftUI

enum Theme {

    // MARK: - Brand color
    // Matches Android rh_accent = #008B8B exactly (R:0 G:139 B:139).
    static let brandTeal = Color(red: 0.0, green: 139.0/255.0, blue: 139.0/255.0)

    // Near-black surface for long-form input editors (custom instructions, chat composer).
    // Deliberate dark field style (owner request) — white text sits on this. Not a themeable
    // semantic surface, hence a fixed value rather than a material.
    static let inputSurfaceDark = Color(red: 0.10, green: 0.10, blue: 0.11)

    // MARK: - Spacing
    // Maps to: xs=4, s=8, m=16 (screen margin + card padding), l=24, xl=32
    // Android: rh_screen_margin=16dp, rh_card_gap=18dp, rh_card_padding=16dp
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat  = 8
        static let m: CGFloat  = 16
        static let l: CGFloat  = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        // Card breathing room — a touch more than `m`. Used for GlassCard inner padding AND the
        // gap between cards, so inner/outer spacing stays consistent everywhere (one place to tune).
        static let cardPadding: CGFloat = 20
    }

    // MARK: - Corner radii
    // Android: card=18dp, dialog/sheet=22dp, icon-container=14dp, input=12dp
    enum CornerRadius {
        static let card: CGFloat   = 20   // GlassCard
        static let sheet: CGFloat  = 22   // bottom sheet top corners
        static let button: CGFloat = 12   // filled action buttons
        static let icon: CGFloat   = 14   // icon container backgrounds
        static let input: CGFloat  = 12   // text fields, search bars
    }

    // MARK: - Icon frame sizes
    // Use .font() modifiers for SF Symbols; use these only when an explicit frame is required.
    enum IconSize {
        static let touch: CGFloat  = 44   // minimum tappable touch target
        static let avatar: CGFloat = 44   // profile / doctor initials circles
        static let card: CGFloat   = 30   // primary icon in a card row
        static let inline: CGFloat = 20   // secondary inline icon
    }
}

