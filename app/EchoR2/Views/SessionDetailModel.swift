import Foundation
import Observation

@MainActor @Observable
final class SessionDetailModel {
    let sessionId: String
    var chat: [ChatLine] = []
    var state: String
    var status: StreamStatus = .connecting
    var readOnly: Bool
    var notFound = false

    /// Retained reconnect cursor: survives stop()/start() so a new stream replays only the delta.
    @ObservationIgnored var cursor: StreamState?
    @ObservationIgnored private var stream: SessionStream?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    init(sessionId: String, info: SessionInfo?) {
        self.sessionId = sessionId
        state = info?.state ?? "unknown"
        readOnly = info?.isExternal ?? false
    }

    /// Late info (the model is created before the view can see app.sessions).
    func adopt(_ i: SessionInfo) {
        if i.isExternal { readOnly = true }
        if chat.isEmpty, state == "unknown" { state = i.state }
    }

    func start(app: AppModel) {
        guard stream == nil, let base = HubClient.baseURL(from: app.host), let token = app.token else { return }
        let s = SessionStream(base: base, token: token, sessionId: sessionId, initialState: cursor)
        stream = s
        Task { await s.start() }
        consumeTask = Task { [weak self] in
            for await out in s.outputs { self?.handle(out, app: app) }
        }
    }

    func stop() {
        let s = stream
        consumeTask?.cancel()
        consumeTask = nil
        stream = nil
        if let s { Task { await s.stop() } }
    }

    private func handle(_ out: StreamOutput, app: AppModel) {
        switch out {
        case .cursor(let s): cursor = s
        case .effect(.resetUI): chat = []
        case .effect(.chat(let l)): chat.append(l)
        case .effect(.state(let s)): state = s
        case .effect(.error(let e)): if e == "read_only" { readOnly = true }
        case .effect(.term): break  // 03-05 feeds the terminal
        case .alive: app.markOK()
        case .status(let s):
            status = s
            switch s {
            case .live: app.markOK()
            case .reconnecting: app.connectionState = .unreachable("Reconnecting")
            case .unauthorized: app.handle(HubError.unauthorized)
            case .gone: notFound = true
            case .connecting: break
            }
        }
    }

    func send(_ text: String) async {
        guard !readOnly else { return }
        await stream?.send(.input(text))
    }

    func interrupt() async {
        guard !readOnly else { return }
        await stream?.send(.interrupt)
    }

    func stopSession(app: AppModel) async {
        guard !readOnly, let c = app.client() else { return }
        do { try await c.stop(id: sessionId) } catch { app.handle(error) }
    }
}
