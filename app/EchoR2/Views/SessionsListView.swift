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
                    ForEach(app.sessions) { SessionRow(session: $0) }
                }
                .padding(Spacing.l)
                .opacity(unreachable ? 0.5 : 1)
            }
        }
        .refreshable { await app.refreshSessions() }
        // Cancelled by SwiftUI when the view disappears or the scene backgrounds.
        .task { await app.pollSessions() }
        .navigationTitle("echo")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New session")
            }
        }
        .sheet(isPresented: $showNew) {
            NewSessionView { _ in }
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

    private func color(_ t: ChipTone) -> Color {
        switch t {
        case .primary: Palette.primaryDeep
        case .warning: Palette.warning
        case .success: Palette.success
        case .muted: Palette.textMuted
        case .danger: Palette.danger
        case .accent: Palette.accentDeep
        }
    }

    var body: some View {
        let chip = session.chip
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(session.displayTitle).font(Typography.heading).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer()
                    Text(chip.text)
                        .font(Typography.caption)
                        .padding(.horizontal, Spacing.m).padding(.vertical, 4)
                        .background(color(chip.tone).opacity(0.25), in: Capsule())
                        .foregroundStyle(Palette.ink)
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
