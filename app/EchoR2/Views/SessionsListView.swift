import SwiftUI

struct SessionsListView: View {
    @Environment(AppModel.self) private var app
    @State private var showNew = false

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
                    ForEach(app.sessions) { s in
                        NavigationLink(value: s.id) { SessionRow(session: s) }.buttonStyle(.plain)
                            .accessibilityIdentifier("sessions.row.\(s.id)")
                    }
                }
                .padding(Spacing.l)
                .opacity(unreachable ? 0.5 : 1)
            }
        }
        .accessibilityIdentifier("sessions.list")
        .refreshable { await app.refreshSessions() }
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

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(session.displayTitle).font(Typography.heading).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer()
                    StateChip(session: session)
                }
                if session.isExternal {
                    if let l = session.label, !l.isEmpty {
                        Text(l).font(Typography.callout).foregroundStyle(Palette.textSecondary)
                    }
                } else if let d = session.startedDate {
                    Text("started " + Self.relative.localizedString(for: d, relativeTo: Date()))
                        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
                }
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
        case .accent: Palette.accentDeep
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
