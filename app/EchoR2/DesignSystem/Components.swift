import SwiftUI

/// Reusable primitives (app/DESIGN.md). Paper cards, hairline borders, spring press states.
/// Buttons do not fire haptics themselves: callers fire the semantic haptic for the outcome.

// MARK: - Screen background

extension View {
    /// Lavender atmosphere behind a screen, including inside a NavigationStack
    /// (whose own container background would otherwise be system white/black).
    func screenBackground() -> some View {
        background { BackgroundAtmosphere() }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.l

    init(padding: CGFloat = Spacing.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Palette.paper, in: .rect(cornerRadius: Spacing.cornerLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.75)
            )
            .shadow(color: Palette.ink.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var icon: String? = nil
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(Palette.textOnDark)
                } else if let icon {
                    Image(systemName: icon).font(Typography.bodyEmph)
                }
                Text(title).font(Typography.bodyEmph)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, Spacing.xl)
            .foregroundStyle(Palette.textOnDark)
            .background(Palette.primaryDeep, in: .rect(cornerRadius: Spacing.cornerMedium, style: .continuous))
            .shadow(color: Palette.primaryDeep.opacity(isEnabled ? 0.22 : 0), radius: 10, x: 0, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .motion(Motion.snappy, value: isEnabled)
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "\(title), in progress" : title)
    }
}

struct SecondaryButton: View {
    let title: String
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.bodyEmph)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(destructive ? Palette.danger : Palette.primaryDeep)
                .background(destructive ? Palette.paper : Palette.surfaceAlt,
                            in: .rect(cornerRadius: Spacing.cornerMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous)
                        .stroke(destructive ? Palette.danger.opacity(0.35) : Palette.border, lineWidth: 0.75)
                )
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Group title

/// Serif title above a group of content (replaces tracked-uppercase eyebrows).
struct GroupTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typography.titleSmall)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Label / value row

/// Settings-style row. Side by side normally, stacked at accessibility sizes so
/// values wrap instead of truncating.
struct LabeledRow: View {
    let label: String
    let value: String
    var mono = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { labelText; Spacer(minLength: Spacing.m); valueText }
            VStack(alignment: .leading, spacing: 2) { labelText; valueText }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label).font(Typography.callout).foregroundStyle(Palette.textSecondary)
    }
    private var valueText: some View {
        Text(value).font(mono ? Typography.mono : Typography.callout).foregroundStyle(Palette.ink)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - States

struct EmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "leaf"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(Palette.primaryDeep.opacity(0.7))
                .accessibilityHidden(true)
            Text(title).font(Typography.title).foregroundStyle(Palette.ink)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action).padding(.top, Spacing.s)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// Loading placeholder in the real row shape.
struct SkeletonRow: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                bar(width: 160, height: 16)
                bar(width: 240, height: 12)
                bar(width: 80, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Palette.surfaceAlt).frame(width: width, height: height)
    }
}
