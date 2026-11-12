import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: SessionDetailModel
    let info: SessionInfo?

    @State private var draft = ""
    @State private var atBottom = true

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.readOnly {
                Card {
                    Text("Watching — started in \(info?.label ?? "terminal")")
                        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("detail.watchingHeader")
                    PrimaryButton(title: "Continue here", action: { Task { await model.continueHere(app: app) } }, isLoading: model.busy)
                    .accessibilityIdentifier("detail.continueHere")
                }
                .padding(Spacing.m)
            }
            if model.trustPrompt {
                Card {
                    Text("Claude is asking to trust this folder. Open Terminal to answer.")
                        .font(Typography.callout).foregroundStyle(Palette.ink)
                    SecondaryButton(title: "Open Terminal") { model.tab = .terminal }
                }
                .overlay(RoundedRectangle(cornerRadius: Spacing.cornerLarge).stroke(Palette.warning, lineWidth: 1.5))
                .padding(Spacing.m)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.s) {
                        if model.olderCursor != nil {
                            Color.clear.frame(height: 1).onAppear {
                                Task {
                                    let first = model.chat.first?.id
                                    await model.loadOlder(app: app)
                                    if let first { proxy.scrollTo(first, anchor: .top) }
                                }
                            }
                        }
                        if model.historyState == .loaded, model.chat.isEmpty {
                            Text("No messages yet").font(Typography.callout).foregroundStyle(Palette.textSecondary)
                                .accessibilityIdentifier("detail.history.empty")
                        }
                        if case .failed(let msg) = model.historyState {
                            VStack(spacing: Spacing.s) {
                                Text(msg).font(Typography.callout).foregroundStyle(Palette.textSecondary)
                                SecondaryButton(title: "Retry") { model.retryHistory(app: app) }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("detail.error")
                        }
                        ForEach(model.chat) { Row(line: $0) }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(Spacing.l)
                }
                .onChange(of: model.chat.count) {
                    if atBottom { proxy.scrollTo("bottom") }
                }
                .overlay(alignment: .bottom) {
                    if !atBottom {
                        Button("Jump to latest") { withAnimation { proxy.scrollTo("bottom") } }
                            .font(Typography.caption)
                            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
                            .background(Palette.paper, in: Capsule())
                            .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
                            .padding(.bottom, Spacing.s)
                    }
                }
            }
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if !model.readOnly {
            HStack(alignment: .bottom, spacing: Spacing.m) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(Spacing.m)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
                    .accessibilityIdentifier("detail.composer")
                Button {
                    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    // No optimistic echo: the transcript event renders the message.
                    Task { await model.send(t, app: app) }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("detail.send")
            }
            .padding(Spacing.m)
        }
    }

    private struct Row: View {
        let line: ChatLine

        private var markdown: Text {
            let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            if let a = try? AttributedString(markdown: line.text, options: o) { return Text(a) }
            return Text(line.text)
        }

        var body: some View {
            if let tool = line.tool {
                Text("\(tool) \(line.text)")
                    .font(Typography.mono).foregroundStyle(Palette.textMuted)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if line.role == "user" {
                markdown.font(Typography.body).foregroundStyle(Palette.ink)
                    .padding(Spacing.m)
                    .background(Palette.primary, in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, Spacing.xxl)
            } else {
                Card(padding: Spacing.m) { markdown.font(Typography.body).foregroundStyle(Palette.ink) }
                    .padding(.trailing, Spacing.xxl)
            }
        }
    }
}
