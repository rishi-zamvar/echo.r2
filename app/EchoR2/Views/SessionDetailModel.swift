import Foundation
import Observation
import SwiftTerm
import SwiftUI
import UIKit

@MainActor @Observable
final class SessionDetailModel {
    let sessionId: String
    var chat: [ChatLine] = []
    var state: String
    var status: StreamStatus = .connecting
    var readOnly: Bool
    var notFound = false
    var trustPrompt = false

    enum Tab: String { case chat, terminal }
    var tab: Tab {
        didSet { if !readOnly { UserDefaults.standard.set(tab.rawValue, forKey: "tab.\(sessionId)") } }
    }

    /// Created once and owned here so scrollback survives Chat <-> Terminal switches.
    @ObservationIgnored let terminal: TerminalView
    @ObservationIgnored private var trust = TrustDetector()
    @ObservationIgnored private var sawLive = false
    @ObservationIgnored private var termQueue: [Data] = []
    @ObservationIgnored private var lastSize: (Int, Int)?  // TerminalView.getTerminal() is internal; track via sizeChanged
    @ObservationIgnored private var feeding = false
    @ObservationIgnored private var resizeTask: Task<Void, Never>?

    /// Retained reconnect cursor: survives stop()/start() so a new stream replays only the delta.
    @ObservationIgnored var cursor: StreamState?
    @ObservationIgnored private var stream: SessionStream?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    init(sessionId: String, info: SessionInfo?) {
        self.sessionId = sessionId
        state = info?.state ?? "unknown"
        readOnly = info?.isExternal ?? false
        let saved = UserDefaults.standard.string(forKey: "tab.\(sessionId)").flatMap(Tab.init(rawValue:))
        tab = (info?.isExternal ?? false) ? .chat : (saved ?? .chat)
        let t = TerminalView(frame: .zero, font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             options: TerminalOptions(scrollback: 5000))
        t.nativeBackgroundColor = UIColor(Palette.ink)
        t.nativeForegroundColor = UIColor(Palette.textOnDark)
        t.allowMouseReporting = false  // T-03-22
        t.inputAccessoryView = nil  // ExtraKeysBar replaces it
        terminal = t
    }

    /// Late info (the model is created before the view can see app.sessions).
    func adopt(_ i: SessionInfo) {
        if i.isExternal { readOnly = true; tab = .chat }
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
        case .effect(.resetUI):
            chat = []
            termQueue = []
            terminal.feed(text: "\u{1b}c")  // RIS
            trust.reset(); trustPrompt = false; sawLive = false
        case .effect(.chat(let l)): chat.append(l)
        case .effect(.state(let s)): state = s
        case .effect(.error(let e)): if e == "read_only" { readOnly = true }
        case .effect(.term(let d, let replay)):
            termQueue.append(d)
            if !replay {
                // Historical ring bytes never raise the banner; live bytes replace (not OR) the flag.
                sawLive = true
                trustPrompt = trust.feed(d)
            }
            drainTerm()
        case .alive: app.markOK()
        case .status(let s):
            status = s
            switch s {
            case .live: app.markOK(); sendSize()
            case .reconnecting: app.connectionState = .unreachable("Reconnecting")
            case .unauthorized: app.handle(HubError.unauthorized)
            case .gone: notFound = true
            case .connecting: break
            }
        }
    }

    /// Feeds queued bytes in 64 KB slices, yielding between slices (pitfall 5).
    private func drainTerm() {
        guard !feeding else { return }
        feeding = true
        Task { [weak self] in
            while let self, !self.termQueue.isEmpty {
                let bytes = [UInt8](self.termQueue.removeFirst())
                var i = 0
                while i < bytes.count {
                    let j = min(i + 65536, bytes.count)
                    self.terminal.feed(byteArray: bytes[i..<j])
                    i = j
                    await Task.yield()
                }
            }
            self?.feeding = false
        }
    }

    func sendKeys(_ s: String) async {
        guard !readOnly else { return }
        trustPrompt = false; trust.reset()
        await stream?.send(.keys(s))
    }

    func resize(cols: Int, rows: Int) {
        lastSize = (cols, rows)
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.readOnly else { return }
            await self.stream?.send(.resize(cols: cols, rows: rows))
        }
    }

    private func sendSize() {
        if let (c, r) = lastSize { resize(cols: c, rows: r) }
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
