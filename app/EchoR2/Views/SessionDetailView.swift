import SwiftUI

struct SessionDetailView: View {
    let sessionId: String
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SessionDetailModel
    @State private var confirmStop = false
    @State private var flash = false
    @AppStorage("terminalDark") private var terminalDark = false
    @Namespace private var tabNS

    init(sessionId: String) {
        self.sessionId = sessionId
        _model = State(initialValue: SessionDetailModel(sessionId: sessionId, info: nil))
    }

    private var info: SessionInfo? { app.sessions.first { $0.id == sessionId } }

    /// info with the stream's live state, so the pill updates without waiting for the list poll.
    private var liveInfo: SessionInfo? {
        guard var i = info else { return nil }
        i.state = model.state
        return i
    }

    private var resumable: Bool {
        guard let i = info, !i.isExternal else { return false }
        return model.state == "stopped" || model.state == "exited"
    }

    private var showTerminal: Bool { model.tab == .terminal && !model.readOnly }

    var body: some View {
        VStack(spacing: 0) {
            if let i = liveInfo { header(i) }
            if !model.readOnly { tabs.transition(.opacity) }
            ZStack {
                if showTerminal {
                    TerminalCard(model: model)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                } else {
                    ChatView(model: model, info: info)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .motion(Motion.gentle, value: model.readOnly)
        .screenBackground()
        .overlay {
            if model.notFound { Text("Session not found").font(Typography.heading).foregroundStyle(Palette.ink) }
        }
        .navigationTitle(info?.displayTitle ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.busy {
                ToolbarItem(placement: .topBarTrailing) { ProgressView().tint(Palette.textMuted) }
            }
            if !model.readOnly {
                ToolbarItem(placement: .topBarTrailing) { actions }
            }
        }
        .alert("Couldn't complete", isPresented: Binding(get: { model.actionError != nil },
                                                        set: { if !$0 { model.actionError = nil } })) {
            Button("OK") { model.actionError = nil }
        } message: { Text(model.actionError ?? "") }
        .confirmationDialog("Stop this session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { Task { await model.stopSession(app: app) } }
        } message: { Text("Claude stops where it is. You can resume it later.") }
        .onAppear {
            if let i = info { model.adopt(i) }
            model.start(app: app)
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, p in
            if p == .background { model.stop() } else if p == .active { model.start(app: app) }
        }
        .onChange(of: model.notFound) { _, gone in
            if gone, !resumable, app.path.last == sessionId { app.path.removeLast() }
        }
        .onChange(of: model.state) { old, new in
            guard old != "unknown" else { return }
            Haptics.stateChange()
            if new == "waiting" { flashPill() }
        }
    }

    // MARK: - Header

    /// Summary (or folder) beside the state pill; the title lives in the nav bar.
    private func header(_ i: SessionInfo) -> some View {
        let summary = i.summary.flatMap { $0.isEmpty || $0 == i.displayTitle ? nil : $0 }
        return HStack(alignment: .center, spacing: Spacing.m) {
            Group {
                if let summary {
                    Text(summary).font(Typography.callout).foregroundStyle(Palette.textSecondary)
                } else {
                    Text(i.cwd).font(Typography.caption.monospaced()).foregroundStyle(Palette.textMuted)
                        .truncationMode(.middle)
                }
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s) {
                if i.activity == .running { LiveDot() }
                StateChip(session: i)
            }
            .padding(Spacing.xs)
            .background(Palette.accent.opacity(flash ? 0.55 : 0), in: .capsule)
        }
        .padding(.horizontal, Spacing.l).padding(.top, Spacing.xs).padding(.bottom, Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.header")
    }

    /// Waiting needs Rishi: a brief rose wash behind the pill.
    private func flashPill() {
        Motion.animate(Motion.snappy) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            Motion.animate(Motion.gentle) { flash = false }
        }
    }

    // MARK: - Chat / Terminal toggle

    private var tabs: some View {
        HStack(spacing: 0) {
            tab(.chat, "Chat", "bubble.left.and.bubble.right")
            tab(.terminal, "Terminal", "apple.terminal")
        }
        .padding(3)
        .background(Palette.surfaceAlt, in: .capsule)
        .overlay(Capsule().stroke(Palette.border, lineWidth: 0.5))
        .padding(.horizontal, Spacing.l).padding(.bottom, Spacing.s)
    }

    private func tab(_ t: SessionDetailModel.Tab, _ title: String, _ icon: String) -> some View {
        let selected = model.tab == t
        return Button {
            guard !selected else { return }
            Haptics.toggle()
            Motion.animate(Motion.snappy) { model.tab = t }
        } label: {
            Label(title, systemImage: icon)
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if selected {
                        Capsule().fill(Palette.paper)
                            .shadow(color: Palette.ink.opacity(0.08), radius: 4, x: 0, y: 1)
                            .matchedGeometryEffect(id: "tabSelection", in: tabNS)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("detail.tab.\(t.rawValue)")
    }

    // MARK: - Actions

    private var actions: some View {
        Menu {
            if resumable {
                Button("Resume", systemImage: "play") { Haptics.send(); Task { await model.resume(app: app) } }
            } else {
                Button("Interrupt", systemImage: "pause") { Haptics.toggle(); Task { await model.interrupt() } }
                Button("Stop", systemImage: "stop", role: .destructive) { Haptics.destructive(); confirmStop = true }
            }
            if showTerminal {
                Divider()
                Toggle("Dark terminal", systemImage: "moon", isOn: $terminalDark)
            }
        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Palette.primaryDeep) }
            .accessibilityLabel("Session actions")
            .disabled(model.busy)
            .onChange(of: terminalDark) { Haptics.toggle() }
    }
}
