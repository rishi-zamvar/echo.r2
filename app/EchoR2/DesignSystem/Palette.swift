import SwiftUI

/// Apothecary editorial palette. Pale lavender canvas, warm paper-cream cards,
/// sage primary, dusty rose accent, deep warm ink. Light only (see app/DESIGN.md).
/// Contrast ratios for every text role are listed in DESIGN.md; all pass AA.
enum Palette {
    // MARK: - Atmosphere (canvas + cards)
    /// Pale lavender canvas, rendered through `BackgroundAtmosphere`.
    static let canvas = Color(red: 0.965, green: 0.955, blue: 0.985)
    /// Warm paper cream: cards, rows, sheets, fields.
    static let paper = Color(red: 0.992, green: 0.984, blue: 0.965)
    /// Pale sage tint for inset surfaces (secondary buttons, skeletons).
    static let surfaceAlt = Color(red: 0.945, green: 0.955, blue: 0.935)

    // MARK: - Brand
    static let primary = Color(red: 0.62, green: 0.74, blue: 0.65)
    /// Primary button fill + tint. Paper text on it is 5.0:1.
    static let primaryDeep = Color(red: 0.32, green: 0.46, blue: 0.38)
    static let accent = Color(red: 0.92, green: 0.74, blue: 0.74)
    /// Sage-tinted paper for the user's chat bubbles (ink text on it is 11:1).
    static let userBubble = Color(red: 0.86, green: 0.91, blue: 0.86)

    // MARK: - Ink (text)
    static let ink = Color(red: 0.20, green: 0.17, blue: 0.16)
    static let textSecondary = Color(red: 0.36, green: 0.32, blue: 0.30)
    static let textMuted = Color(red: 0.45, green: 0.41, blue: 0.39)
    static let textOnDark = paper

    // MARK: - Session state roles
    static let running = Color(red: 0.27, green: 0.40, blue: 0.32)
    static let needsYou = Color(red: 0.58, green: 0.30, blue: 0.30)
    static let idle = textMuted

    // MARK: - Semantic
    static let success = running
    static let warning = Color(red: 0.55, green: 0.38, blue: 0.12)
    static let danger = Color(red: 0.66, green: 0.26, blue: 0.24)

    // MARK: - Hairlines
    static let border = Color(red: 0.86, green: 0.84, blue: 0.80)
    static let divider = Color(red: 0.90, green: 0.88, blue: 0.84)

    // MARK: - Atmosphere helpers
    static let meshSage = Color(red: 0.72, green: 0.84, blue: 0.74).opacity(0.55)
    static let meshRose = Color(red: 0.94, green: 0.80, blue: 0.82).opacity(0.45)
    static let grainInk = Color(red: 0.18, green: 0.15, blue: 0.13)
}
