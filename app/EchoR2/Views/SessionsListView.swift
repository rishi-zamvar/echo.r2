import SwiftUI

struct SessionsListView: View {
    @Environment(AppModel.self) private var app
    @State private var showNew = false
    @State private var showOther = false

    private var main: [SessionInfo] { app.sessions.filter { $0.noise != true } }
    private var other: [SessionInfo] { app.sessions.filter { $0.noise == true } }

    private func link(_ s: SessionInfo) -> some View {
        NavigationLink(value: s.id) { SessionRow(session: s) }.buttonStyle(.plain)
            .accessibilityIdentifier("sessions.row.\(s.id)")
    }

    private var unreachable: Bool {
        if case .unreachable = app.connectionState { return true }
        return false
    }

    var body: some View {
        ScrollView {
            if !app.sessionsLoaded && app.sessions.isEmpty {
                ProgressView().padding(.top, Spacing.xxl)
            } else if app.sessions.isEmpty {
                EmptyState(title: "No sessions", message: "Tap + to start.", systemImage: "terminal")
            } else {
                LazyVStack(spacing: Spacing.m) {
                    ForEach(main) { link($0) }
                    if !other.isEmpty {
                        Button {
                            Haptics.toggle()
                            withAnimation(.spring) { showOther.toggle() }
                        } label: {
                            HStack {
                                Text("Other (\(other.count))").font(Typography.callout)
                                Spacer()
                                Image(systemName: showOther ? "chevron.up" : "chevron.down")
                            }
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.top, Spacing.s)
                        }
                        .accessibilityIdentifier("sessions.other.toggle")
                        if showOther { ForEach(other) { link($0) } }
                    }
                }
                .padding(Spacing.l)
                .opacity(unreachable ? 0.5 : 1)
            }
        }
        .accessibilityIdentifier("sessions.list")
        .refreshable { Haptics.arrival(); await app.refreshSessions() }
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
            }
        }
        .navigationDestination(for: String.self) { SessionDetailView(sessionId: $0) }
        .sheet(isPresented: $showNew) {
            NewSessionView { app.path.append($0) }
        }
    }
}

private struct SessionRow: View {
    let session: SessionInfo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

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

    private var when: Date? { session.lastActivityDate ?? session.startedDate }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    if session.activity == .running {
                        Circle().fill(Palette.primaryDeep).frame(width: 8, height: 8)
                            .opacity(reduceMotion ? 1 : (pulse ? 0.35 : 1))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                            .onAppear { pulse = true }
                    }
                    Text(session.displayTitle).font(Typography.heading).foregroundStyle(titleColor).lineLimit(1)
                    Spacer()
                    StateChip(session: session)
                }
                if let sum = session.summary, !sum.isEmpty, sum != session.displayTitle {
                    Text(sum).font(Typography.callout).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                HStack {
                    if session.isExternal, let l = session.label, !l.isEmpty { Text(l) }
                    Spacer()
                    if let d = when { Text(Self.relative.localizedString(for: d, relativeTo: Date())) }
                }
                .font(Typography.caption).foregroundStyle(Palette.textMuted)
            }
        }
    }
}

/// State capsule shared by the list and the detail toolbar.
struct StateChip: View {
    let session: SessionInfo

    private var color: Color {
        switch session.chip.tone {
        case .primary: Palette.primaryDeep
        case .warning: Palette.warning
        case .success: Palette.success
        case .muted: Palette.textMuted
        case .danger: Palette.danger
        case .accent: Palette.needsYou
        }
    }

    var body: some View {
        Text(session.chip.text)
            .font(Typography.caption)
            .padding(.horizontal, Spacing.m).padding(.vertical, 4)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(Palette.ink)
    }
}
