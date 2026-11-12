import Foundation
import Network

enum StreamStatus: Sendable { case connecting, live, reconnecting, gone, unauthorized }

enum StreamOutput: Sendable {
    case effect(Effect)
    case cursor(StreamState)
    case status(StreamStatus)
    case alive
}

/// Self-healing authenticated WebSocket to one session (D-11/D-12/D-25).
/// The state (since/epoch) survives reconnects; seed `initialState` to survive a new stream.
actor SessionStream {
    nonisolated let outputs: AsyncStream<StreamOutput>
    private let out: AsyncStream<StreamOutput>.Continuation
    private let base: URL
    private let token: String
    private let sessionId: String
    private var state: StreamState
    private var runTask: Task<Void, Never>?
    private var backoffTask: Task<Void, Never>?
    private var ws: URLSessionWebSocketTask?
    private var monitor: NWPathMonitor?
    private var pathSig: String?
    private var skipBackoff = false

    init(base: URL, token: String, sessionId: String, initialState: StreamState?) {
        self.base = base
        self.token = token
        self.sessionId = sessionId
        self.state = initialState ?? StreamState()
        (outputs, out) = AsyncStream.makeStream(of: StreamOutput.self)
    }

    func start() {
        guard runTask == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            let sig = path.availableInterfaces.map { "\($0.type)" }.sorted().joined(separator: ",")
            Task { await self?.pathChanged(satisfied: ok, signature: sig) }
        }
        m.start(queue: DispatchQueue(label: "echo.path"))
        monitor = m
        runTask = Task { await self.run() }
    }

    func stop() {
        runTask?.cancel()
        backoffTask?.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        monitor?.cancel()
        runTask = nil
        out.finish()
    }

    func send(_ f: ClientFrame) async {
        guard let ws, ws.state == .running else { return }
        try? await ws.send(.string(f.json()))
    }

    // MARK: - run loop

    private func request() -> URLRequest? {
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        c.path = "/sessions/\(sessionId)/stream"
        var q = [URLQueryItem(name: "since", value: String(state.lastSeq))]
        if let e = state.epoch { q.append(URLQueryItem(name: "epoch", value: e)) }
        c.queryItems = q
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url)
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return r
    }

    private func finish(_ s: StreamStatus) {
        out.yield(.status(s))
        monitor?.cancel()
        out.finish()
    }

    private func run() async {
        var backoff = 0.5
        var first = true
        while !Task.isCancelled {
            guard let req = request() else { return finish(.gone) }
            out.yield(.status(first ? .connecting : .reconnecting))
            first = false
            let t = URLSession.shared.webSocketTask(with: req)
            ws = t
            t.resume()
            let ping = Task { await self.pingLoop(t) }
            do {
                while true {
                    guard case .string(let s) = try await t.receive() else { continue }
                    var gotHello = false
                    if case .hello = Frame.decode(s) { gotHello = true }
                    for e in apply(Frame.decode(s), to: &state) { out.yield(.effect(e)) }
                    out.yield(.cursor(state))
                    if gotHello { backoff = 0.5; out.yield(.status(.live)) }
                }
            } catch {}
            ping.cancel()
            if Task.isCancelled { return }
            let code = t.closeCode.rawValue
            if code == 4404 { return finish(.gone) }
            if code == 4401 || (t.response as? HTTPURLResponse)?.statusCode == 401 { return finish(.unauthorized) }
            out.yield(.status(.reconnecting))
            if skipBackoff {
                skipBackoff = false
            } else {
                let delay = backoff
                backoff = min(backoff * 2, 15)
                let s = Task<Void, Never> { try? await Task.sleep(for: .seconds(delay)) }
                backoffTask = s
                await withTaskCancellationHandler { await s.value } onCancel: { s.cancel() }
                backoffTask = nil
            }
        }
    }

    // MARK: - liveness

    private func pingLoop(_ t: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            if Task.isCancelled { return }
            let ok = await withTaskGroup(of: Bool.self) { g in
                g.addTask { await withCheckedContinuation { c in t.sendPing { c.resume(returning: $0 == nil) } } }
                g.addTask { try? await Task.sleep(for: .seconds(10)); return false }
                let first = await g.next() ?? false
                // Cancelling the socket also fires the ping callback, so the group can drain.
                if !first && !Task.isCancelled { t.cancel(with: .goingAway, reason: nil) }
                g.cancelAll()
                return first
            }
            if ok { out.yield(.alive) } else { return }
        }
    }

    private func pathChanged(satisfied: Bool, signature: String) {
        defer { pathSig = signature }
        guard satisfied, let prev = pathSig, prev != signature, runTask != nil else { return }
        if let b = backoffTask {
            b.cancel()  // reconnecting: skip the remaining sleep
        } else if let ws {
            skipBackoff = true  // live socket on the old interface is usually dead
            ws.cancel(with: .goingAway, reason: nil)
        }
    }
}
