import SwiftUI

/// The conversation (D-13): bubbles with inline markdown, tool runs collapsed to "Used N tools",
/// a live working indicator, a jump-to-latest pill, and designed loading/empty/error states.
struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: SessionDetailModel
    let info: SessionInfo?

    @State private var draft = ""
    @State private var atBottom = true
    @State private var expanded: Set<String> = []
    @FocusState private var composerFocused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
    }

    /// Claude is producing output right now (live hub session only).
    private var working: Bool {
        !model.readOnly && !model.historyOnly && (model.state == "running" || model.state == "starting")
    }

    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.readOnly { watchingCard.transition(.opacity) }
            if model.trustPrompt { trustCard.transition(.opacity) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.m) {
                        if model.olderCursor != nil {
                            ProgressView().tint(Palette.textMuted).padding(Spacing.s).onAppear {
                                Task {
                                    let first = model.chat.first?.id
                                    await model.loadOlder(app: app)
                                    if let first { proxy.scrollTo(first, anchor: .top) }
                                }
                            }
                        }
                        stateView
                        ForEach(ChatGroup.group(model.chat)) { item in
                            row(item).transition(arrival)
                        }
                        if working {
                            WorkingBubble().transition(arrival)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.m)
                    .motion(Motion.list, value: model.chat.count)
                    .motion(Motion.gentle, value: working)
                    .motion(Motion.gentle, value: model.historyState)
                }
                .scrollDismissesKeyboard(.interactively)
                // Geometry, not sentinel onAppear/onDisappear: the sentinel flip-flopped with the keyboard up
                // and re-rendered forever. A Bool only fires when it actually changes.
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40
                } action: { _, v in atBottom = v }
                .onChange(of: model.chat.last?.id) { old, _ in
                    if atBottom { Motion.animate(Motion.list) { proxy.scrollTo("bottom", anchor: .bottom) } }
                    // Live arrivals only: the initial load and stream replays don't change an existing last id.
                    if old != nil, model.historyState == .loaded, model.chat.last?.role != "user" { Haptics.arrival() }
                }
                .onChange(of: working) { if atBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
                .overlay(alignment: .bottom) {
                    ZStack { if !atBottom {
                        Button {
                            Haptics.toggle()
                            Motion.animate(Motion.gentle) { proxy.scrollTo("bottom", anchor: .bottom) }
                        } label: {
                            Label("Latest", systemImage: "arrow.down")
                                .font(Typography.callout.weight(.semibold))
                                .foregroundStyle(Palette.primaryDeep)
                                .padding(.horizontal, Spacing.l).frame(minHeight: 44)
                                .background(Palette.paper, in: .capsule)
                                .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
                                .shadow(color: Palette.ink.opacity(0.10), radius: 8, x: 0, y: 3)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Jump to latest message")
                        .accessibilityIdentifier("detail.jumpLatest")
                        .padding(.bottom, Spacing.m)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                    } }
                    .motion(Motion.snappy, value: atBottom)
                }
            }
            footer
        }
        .motion(Motion.gentle, value: model.readOnly)
        .motion(Motion.gentle, value: model.trustPrompt)
    }

    // MARK: - States

    @ViewBuilder private var stateView: some View {
        switch model.historyState {
        case .loading where model.chat.isEmpty:
            VStack(spacing: Spacing.m) {
                SkeletonBubble(width: 180, user: true)
                SkeletonBubble(width: 260, user: false)
                SkeletonBubble(width: 140, user: false)
            }
            .accessibilityElement()
            .accessibilityLabel("Loading conversation")
        case .loaded where model.chat.isEmpty && !working:
            EmptyState(title: "No messages yet",
                       message: model.readOnly ? "Nothing has been said in this session yet."
                                               : "Send a message below to get Claude started.",
                       systemImage: "bubble.left.and.text.bubble.right")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.history.empty")
        case .failed(let msg):
            VStack(spacing: Spacing.m) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(Palette.danger)
                    .accessibilityHidden(true)
                Text(msg).font(Typography.body).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                Text("Check the hub is reachable, then try again.")
                    .font(Typography.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                SecondaryButton(title: "Retry") { Haptics.toggle(); model.retryHistory(app: app) }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.error")
        default:
            EmptyView()
        }
    }

    /// External session: say where it lives and offer the one action (D-17).
    private var watchingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label {
                    Text("Watching — started in \(info?.label ?? "a terminal")")
                        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
                } icon: {
                    Image(systemName: "eye").foregroundStyle(Palette.idle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail.watchingHeader")
                PrimaryButton(title: "Continue here", action: { Task { await model.continueHere(app: app) } },
                              isLoading: model.busy, icon: "arrow.down.left.circle")
                    .accessibilityHint("Takes this session over so you can send messages from the phone")
                    .accessibilityIdentifier("detail.continueHere")
            }
        }
        .padding(.horizontal, Spacing.l).padding(.top, Spacing.s)
    }

    private var trustCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Claude is asking to trust this folder. Open Terminal to answer.", systemImage: "hand.raised")
                    .font(Typography.callout).foregroundStyle(Palette.ink)
                SecondaryButton(title: "Open Terminal") { Haptics.toggle(); model.tab = .terminal }
            }
        }
        .padding(.horizontal, Spacing.l).padding(.top, Spacing.s)
    }

    // MARK: - Rows

    @ViewBuilder private func row(_ item: ChatItem) -> some View {
        switch item {
        case .message(let line): Bubble(line: line)
        case .tools(let id, let lines):
            ToolGroup(lines: lines, expanded: expanded.contains(id)) {
                Haptics.toggle()
                Motion.animate(Motion.snappy) {
                    if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
                }
            }
        }
    }

    // MARK: - Composer

    @ViewBuilder private var footer: some View {
        if !model.readOnly {
            HStack(alignment: .bottom, spacing: Spacing.s) {
                TextField("Message Claude", text: $draft, axis: .vertical)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
                    .background(Palette.paper, in: .rect(cornerRadius: Spacing.cornerLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
                            .stroke(composerFocused ? Palette.primaryDeep.opacity(0.5) : Palette.border, lineWidth: 0.75)
                    )
                    .accessibilityIdentifier("detail.composer")
                Button {
                    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    Haptics.send()
                    // No optimistic echo: the transcript event renders the message.
                    Task { await model.send(t, app: app) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Palette.textOnDark)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Palette.primaryDeep : Palette.idle.opacity(0.45), in: .circle)
                        .scaleEffect(canSend ? 1 : 0.9)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .disabled(!canSend)
                .motion(Motion.snappy, value: canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("detail.send")
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Bubble

private struct Bubble: View {
    let line: ChatLine
    /// T-05-29: very long messages render a prefix until asked.
    private static let limit = 20_000
    @State private var showAll = false

    private var isUser: Bool { line.role == "user" }
    private var truncated: Bool { !showAll && line.text.count > Self.limit }
    private var shown: String { truncated ? String(line.text.prefix(Self.limit)) + "…" : line.text }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(Array(MarkdownBlocks.split(shown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let s): MarkdownBlocks.inline(s).font(Typography.body).foregroundStyle(Palette.ink)
                case .code(let s):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(s).font(Typography.mono).foregroundStyle(Palette.ink).padding(Spacing.m)
                    }
                    .background(Palette.surfaceAlt, in: .rect(cornerRadius: Spacing.cornerSmall, style: .continuous))
                }
            }
            if truncated {
                Button("Show more") { Motion.animate(Motion.gentle) { showAll = true } }
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.primaryDeep)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
        .background(isUser ? Palette.userBubble : Palette.paper, in: shape)
        .overlay(shape.stroke(isUser ? Color.clear : Palette.border, lineWidth: 0.75))
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, Spacing.xxl)
        // T-05-28: only web links open; any other scheme in transcript markdown is ignored.
        .environment(\.openURL, OpenURLAction { url in
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Claude"): \(shown)")
    }

    private var shape: UnevenRoundedRectangle {
        let r = Spacing.cornerLarge, tail = Spacing.xs
        return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: isUser ? r : tail,
                                      bottomTrailingRadius: isUser ? tail : r, topTrailingRadius: r,
                                      style: .continuous)
    }
}

/// Fenced code blocks become mono insets; everything else is inline-only markdown (no HTML, no images).
enum MarkdownBlocks {
    enum Block { case text(String), code(String) }

    static func split(_ s: String) -> [Block] {
        s.components(separatedBy: "```").enumerated().compactMap { i, part in
            if i.isMultiple(of: 2) {
                let t = part.trimmingCharacters(in: .newlines)
                return t.isEmpty ? nil : .text(t)
            }
            // Drop the language tag on the fence line.
            let body = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let code = body.count > 1 ? String(body[1]) : part
            return .code(code.trimmingCharacters(in: .newlines))
        }
    }

    static func inline(_ s: String) -> Text {
        let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: o) { return Text(a) }
        return Text(s)
    }
}

// MARK: - Tool group

private struct ToolGroup: View {
    let lines: [ChatLine]
    let expanded: Bool
    let toggle: () -> Void

    private var title: String { lines.count == 1 ? "Used 1 tool" : "Used \(lines.count) tools" }

    /// "Bash: ls -la" already names its tool; others get the name prefixed.
    private func detail(_ l: ChatLine) -> String {
        guard let tool = l.tool, !l.text.hasPrefix(tool) else { return l.text }
        return l.text.isEmpty ? tool : "\(tool): \(l.text)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button(action: toggle) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Palette.primaryDeep)
                        .accessibilityHidden(true)
                    Text(title).font(Typography.callout.weight(.medium)).foregroundStyle(Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Palette.textMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 44)
                .background(Palette.surfaceAlt, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")
            .accessibilityHint(expanded ? "Hides the tool calls" : "Shows the tool calls")
            .accessibilityIdentifier("detail.toolGroup")
            if expanded {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(lines) { l in
                        Text(detail(l))
                            .font(Typography.mono)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.m)
                .background(Palette.paper, in: .rect(cornerRadius: Spacing.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.75))
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Working + skeleton

private struct WorkingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.s) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    if reduceMotion {
                        dot.opacity(0.7)
                    } else {
                        dot.phaseAnimator([0.3, 1.0]) { v, p in v.opacity(p).scaleEffect(0.8 + 0.2 * p) } animation: { _ in
                            .easeInOut(duration: 0.6).delay(Double(i) * 0.18)
                        }
                    }
                }
            }
            Text("Working").font(Typography.callout).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.l).frame(minHeight: 44)
        .background(Palette.paper, in: .capsule)
        .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude is working")
        .accessibilityIdentifier("detail.working")
    }

    private var dot: some View { Circle().fill(Palette.running).frame(width: 7, height: 7) }
}

private struct SkeletonBubble: View {
    let width: CGFloat
    let user: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
            .fill(user ? Palette.userBubble.opacity(0.6) : Palette.paper)
            .frame(width: width, height: 44)
            .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
    }
}
