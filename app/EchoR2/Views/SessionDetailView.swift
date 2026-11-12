import SwiftUI

struct SessionDetailView: View {
    let sessionId: String
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SessionDetailModel
    @State private var confirmStop = false

    init(sessionId: String) {
        self.sessionId = sessionId
        _model = State(initialValue: SessionDetailModel(sessionId: sessionId, info: nil))
    }

    private var info: SessionInfo? { app.sessions.first { $0.id == sessionId } }

    /// info with the stream's live state, so the chip updates without waiting for the list poll.
    private var liveInfo: SessionInfo? {
        guard var i = info else { return nil }
        i.state = model.state
        return i
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("Chat").tag(SessionDetailModel.Tab.chat)
                Text("Terminal").tag(SessionDetailModel.Tab.terminal)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
            .disabled(model.readOnly)  // D-17
            if model.tab == .terminal && !model.readOnly {
                TerminalCard(model: model)
            } else {
                ChatView(model: model, info: info)
            }
        }
            .overlay { if model.notFound { Text("Session not found").font(Typography.heading) } }
            .navigationTitle(info?.displayTitle ?? "Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let i = liveInfo { StateChip(session: i) }
                }
                if !model.readOnly {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Interrupt") { Task { await model.interrupt() } }
                            Button("Stop", role: .destructive) { confirmStop = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("Session actions")
                    }
                }
            }
            .confirmationDialog("Stop this session?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop", role: .destructive) { Task { await model.stopSession(app: app) } }
            }
            .onAppear {
                if let i = info { model.adopt(i) }
                model.start(app: app)
            }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { _, p in
                if p == .background { model.stop() } else if p == .active { model.start(app: app) }
            }
            .onChange(of: model.notFound) { _, gone in
                if gone, app.path.last == sessionId { app.path.removeLast() }
            }
    }
}
