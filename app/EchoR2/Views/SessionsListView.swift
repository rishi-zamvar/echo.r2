import SwiftUI

struct SessionsListView: View {
    @Environment(AppModel.self) private var app
    @State private var showNew = false
    @State private var showOther = false

    private var main: [SessionInfo] { app.sessions.filter { $0.noise != true } }
    private var other: [SessionInfo] { app.sessions.filter { $0.noise == true } }

    private var unreachable: Bool {
        if case .unreachable = app.connectionState { return true }
        return false
    }

    private enum Phase { case loading, empty, list }
    private var phase: Phase {
        if app.sessions.isEmpty { return app.sessionsLoaded ? .empty : .loading }
        return .list
    }

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: Spacing.m) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                        .accessibilityElement()
                        .accessibilityLabel("Loading sessions")
                case .empty:
                    EmptyState(title: "No sessions yet",
                               message: "Start Claude on your hub from here. It keeps working when you put the phone away.",
                               systemImage: "sparkles",
                               actionTitle: "Start a session") { showNew = true }
                case .list:
                    list
                }
            }
            .transition(.opacity)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
        .motion(Motion.gentle, value: phase)
        .screenBackground()
        .accessibilityIdentifier("sessions.list")
        .refreshable { Haptics.refresh(); await app.refreshSessions() }
        // Cancelled by SwiftUI when the view disappears or the scene backgrounds.
        .task { await app.pollSessions() }
        .navigationTitle("echo")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("sessions.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New session")
                    .accessibilityIdentifier("sessions.new")
            }
        }
        .navigationDestination(for: String.self) { SessionDetailView(sessionId: $0) }
        .sheet(isPresented: $showNew) {
            NewSessionView { app.path.append($0) }
        }
    }

    private var list: some View {
        LazyVStack(spacing: Spacing.m) {
            ForEach(main) { link($0) }
            if !other.isEmpty {
                otherToggle
                if showOther { ForEach(other) { link($0) } }
            }
        }
        .motion(Motion.list, value: main.map(\.id))
        .motion(Motion.list, value: other.map(\.id))
        .opacity(unreachable ? 0.55 : 1)
        .motion(Motion.gentle, value: unreachable)
    }

    private func link(_ s: SessionInfo) -> some View {
        NavigationLink(value: s.id) { SessionRow(session: s) }
            .buttonStyle(PressableStyle(scale: 0.985))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityIdentifier("sessions.row.\(s.id)")
    }

    private var otherToggle: some View {
        Button {
            Haptics.toggle()
            Motion.animate(Motion.list) { showOther.toggle() }
        } label: {
            HStack {
                Text("Other").font(Typography.titleSmall).foregroundStyle(Palette.ink)
                Text("\(other.count)").font(Typography.callout).foregroundStyle(Palette.textMuted)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(showOther ? 180 : 0))
            }
            .padding(.top, Spacing.l)
            .padding(.horizontal, Spacing.xs)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Other sessions, \(other.count)")
        .accessibilityValue(showOther ? "Shown" : "Hidden")
        .accessibilityHint("One-off and old sessions")
        .accessibilityIdentifier("sessions.other.toggle")
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var titleColor: Color {
        switch session.activity {
        case .running: Palette.ink
        case .needsYou: Palette.needsYou
        case .idle: Palette.textSecondary
        }
    }

    private var when: String? {
        (session.lastActivityDate ?? session.startedDate).map { Self.relative.localizedString(for: $0, relativeTo: .now) }
    }
    private var summary: String? {
        guard let s = session.summary, !s.isEmpty, s != session.displayTitle else { return nil }
        return s
    }
    private var origin: String? {
        guard session.isExternal, let l = session.label, !l.isEmpty else { return nil }
        return l
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text(session.displayTitle)
                        .font(Typography.heading)
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StateChip(session: session)
                }
                if let summary {
                    Text(summary)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(typeSize >= .xxLarge ? 3 : 1)
                }
                HStack(spacing: Spacing.s) {
                    if session.activity == .running {
                        LiveDot()
                        Text("Live").foregroundStyle(Palette.running)
                    }
                    if let origin { Text(origin) }
                    Spacer(minLength: Spacing.s)
                    if let when { Text(when) }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textMuted)
            }
        }
        .onChange(of: session.state) { Haptics.stateChange() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([session.displayTitle, session.chip.text, summary, origin, when].compactMap(\.self).joined(separator: ", "))
        .accessibilityHint("Opens the session")
    }
}

/// State capsule shared by the list and the detail toolbar. Colour and word both carry the state.
struct StateChip: View {
    let session: SessionInfo

    private var color: Color {
        switch session.chip.tone {
        case .primary: Palette.running
        case .warning: Palette.needsYou
        case .accent: Palette.textSecondary
        case .success, .muted, .danger: Palette.idle
        }
    }

    var body: some View {
        Text(session.chip.text)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
            .background(color.opacity(0.12), in: .capsule)
            .fixedSize()
            .contentTransition(.opacity)
            .motion(Motion.snappy, value: session.chip.text)
    }
}
