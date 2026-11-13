import SwiftUI

/// Serif display + SF Rounded body + mono for paths/codes (DESIGN.md "Type").
/// Every style is a Dynamic Type text style so it scales to XXL.
enum Typography {
    // MARK: - Editorial (serif)
    static let display = Font.system(.largeTitle, design: .serif).italic()
    static let title = Font.system(.title, design: .serif)
    static let titleSmall = Font.system(.title3, design: .serif, weight: .medium)

    // MARK: - UI (rounded)
    static let heading = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let bodyEmph = Font.system(.body, design: .rounded, weight: .semibold)
    static let callout = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let mono = Font.system(.subheadline, design: .monospaced)
}
