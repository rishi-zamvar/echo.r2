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
    var actionError: String?
    var busy = false
    var historyState: HistoryState = .loading
    var olderCursor: Int?
    /// Stream said 4404 (stopped/dormant/external): the transcript is shown, nothing is live.
    var historyOnly = false

    enum HistoryState: Equatable { case loading, loaded, failed(String) }

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
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var loadingOlder = false

    init(sessionId: String, info: SessionInfo?) {
        self.sessionId = sessionId
        state = info?.state ?? "unknown"
        readOnly = info?.isExternal ?? false
        let saved = UserDefaults.standard.string(forKey: "tab.\(sessionId)").flatMap(Tab.init(rawValue:))
        tab = (info?.isExternal ?? false) ? .chat : (saved ?? .chat)
        let t = TerminalView(frame: .zero, font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             options: TerminalOptions(scrollback: 5000))
        // D-10: paper/ink by default; the dark theme is an opt-in (applyTerminalTheme).
        t.nativeBackgroundColor = UIColor(Palette.paper)
        t.nativeForegroundColor = UIColor(Palette.ink)
        t.selectedTextBackgroundColor = UIColor(Palette.primary)
        t.allowMouseReporting = false  // T-03-22
        t.inputAccessoryView = nil  // ExtraKeysBar replaces it
        terminal = t
    }

    /// Late info (the model is created before the view can see app.sessions).
    func adopt(_ i: SessionInfo) {
        if i.isExternal { readOnly = true; tab = .chat }
        if chat.isEmpty, state == "unknown" { state = i.state }
    }

    /// Loads history first (once), then opens the live stream; merge-by-index makes the stream replay safe.
    func start(app: AppModel) {
        guard stream == nil, startTask == nil else { return }
        status = .connecting
        historyOnly = false
        startTask = Task { [weak self] in
            guard let self else { return }
            if self.historyState != .loaded { await self.loadHistory(app: app) }
            guard !Task.isCancelled else { return }
            self.startTask = nil
            guard !self.notFound, let base = HubClient.baseURL(from: app.host), let token = app.token else { return }
            let s = SessionStream(base: base, token: token, sessionId: self.sessionId, initialState: self.cursor)
            self.stream = s
            Task { await s.start() }
            self.consumeTask = Task { [weak self] in
                for await out in s.outputs { self?.handle(out, app: app) }
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        let s = stream
        consumeTask?.cancel()
        consumeTask = nil
        stream = nil
        if let s { Task { await s.stop() } }
    }

    func loadHistory(app: AppModel) async {
        guard let c = app.client() else { return }
        historyState = .loading
        do {
            let r = try await c.history(id: sessionId)
            chat = ChatLine.merge(chat, r.lines.map { ChatLine($0) })
            olderCursor = r.before
            historyState = .loaded
        } catch HubError.server("not_found", _) {
            notFound = true
            historyState = .failed("Session not found")
        } catch HubError.unauthorized {
            app.handle(HubError.unauthorized)
        } catch {
            historyState = .failed("Couldn't load the conversation")
        }
    }

    func retryHistory(app: AppModel) {
        stop()
        historyState = .loading
        start(app: app)
    }

    func loadOlder(app: AppModel) async {
        guard let before = olderCursor, !loadingOlder, let c = app.client() else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        if let r = try? await c.history(id: sessionId, before: before) {
            chat = ChatLine.merge(chat, r.lines.map { ChatLine($0) })
            olderCursor = r.before
        }
    }

    private func handle(_ out: StreamOutput, app: AppModel) {
        switch out {
        case .cursor(let s): cursor = s
        case .effect(.resetUI):
            // Chat is kept: index-based merge makes the replay that follows a reset idempotent.
            termQueue = []
            terminal.feed(text: "\u{1b}c")  // RIS
            trust.reset(); trustPrompt = false; sawLive = false
        case .effect(.chat(let l)): chat = ChatLine.merge(chat, [l])
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
            case .reconnecting: app.relayReconnecting()  // D-04: debounced, short hiccups stay quiet
            case .unauthorized: app.handle(HubError.unauthorized)
            case .gone:
                historyOnly = true
                if historyState != .loaded { notFound = true }
            case .connecting: break
            }
        }
    }

    @ObservationIgnored private var themedDark = false
    /// Recolours the existing TerminalView in place (scrollback kept). Dark is warm ink, never black.
    func applyTerminalTheme(dark: Bool) {
        guard dark != themedDark else { return }
        themedDark = dark
        terminal.nativeBackgroundColor = UIColor(dark ? Palette.ink : Palette.paper)
        terminal.nativeForegroundColor = UIColor(dark ? Palette.paper : Palette.ink)
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

    /// Resumes a stopped/exited session first, waits for the stream to be live, then sends.
    func send(_ text: String, app: AppModel) async {
        guard !readOnly, !busy else { return }
        if state == "stopped" || state == "exited" || historyOnly {
            guard await resume(app: app) else { return }
        }
        for _ in 0..<75 where status != .live { try? await Task.sleep(for: .milliseconds(200)) }
        guard status == .live else { actionError = "Couldn't restart the session"; return }
        await stream?.send(.input(text))
    }

    func interrupt() async {
        guard !readOnly else { return }
        await stream?.send(.interrupt)
    }

    func restartStream(app: AppModel) {
        stop()
        start(app: app)
    }

    /// Plain-language text for the hub's guard refusals (D-03); nil for anything else.
    private func refusal(_ e: Error) -> String? {
        guard case .server(let code, _)? = e as? HubError else { return nil }
        switch code {
        case "even_terminal": return "This session is open in Even Terminal. Continue it there, or start a new session here."
        case "live_elsewhere": return "This session is still running somewhere else. Close it there first."
        case "busy": return "It was active in the last minute. Try again shortly."
        default: return nil
        }
    }

    @discardableResult
    func resume(app: AppModel) async -> Bool {
        guard !busy, let c = app.client() else { return false }
        busy = true
        defer { busy = false }
        do {
            try await c.resume(id: sessionId)
            notFound = false
            historyOnly = false
            state = "starting"
            await app.refreshSessions()
            restartStream(app: app)
            return true
        } catch {
            if let m = refusal(error) { actionError = m }
            else if case .server("not_resumable", _)? = error as? HubError { actionError = "Already running" }
            else if case .server("bad_cwd", _)? = error as? HubError { actionError = "Folder is no longer allowed on the hub" }
            else if case .server("claude_unavailable", _)? = error as? HubError { actionError = "Claude is unavailable on the hub" }
            else { app.handle(error); actionError = "Resume failed" }
            Haptics.failure()
            return false
        }
    }

    func continueHere(app: AppModel) async {
        guard !busy, let c = app.client() else { return }
        busy = true
        defer { busy = false }
        do {
            try await c.takeover(id: sessionId)
            readOnly = false
            tab = .chat
            await app.refreshSessions()
            restartStream(app: app)
            Haptics.paired()
        } catch {
            if let m = refusal(error) { actionError = m }
            else { app.handle(error); actionError = "Couldn't continue here" }
            Haptics.failure()
        }
    }

    func stopSession(app: AppModel) async {
        guard !readOnly, let c = app.client() else { return }
        do { try await c.stop(id: sessionId) } catch { app.handle(error) }
    }
}
