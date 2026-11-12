import SwiftUI

struct ChatView: View {
    @Bindable var model: SessionDetailModel
    let info: SessionInfo?

    @State private var draft = ""
    @State private var atBottom = true

    private var ended: Bool { ["exited", "stopped"].contains(model.state) }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.status == .live && !ended
    }

    var body: some View {
        VStack(spacing: 0) {
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
        if model.readOnly {
            note("Watching — started in \(info?.label ?? "terminal")")
        } else if ended {
            note("Session ended")
        } else {
            HStack(alignment: .bottom, spacing: Spacing.m) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(Spacing.m)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))
                Button {
                    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    // No optimistic echo: the transcript event renders the message.
                    Task { await model.send(t) }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
            }
            .padding(Spacing.m)
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Typography.callout).foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity).padding(Spacing.l)
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
