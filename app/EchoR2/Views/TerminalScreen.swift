import SwiftTerm
import SwiftUI

/// Embeds the model-owned TerminalView (never recreated, so scrollback persists).
struct TerminalScreen: UIViewRepresentable {
    let model: SessionDetailModel
    @AppStorage("terminalDark") private var terminalDark = false

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> TerminalView {
        model.terminal.terminalDelegate = context.coordinator
        model.applyTerminalTheme(dark: terminalDark)
        return model.terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) { model.applyTerminalTheme(dark: terminalDark) }

    @MainActor final class Coordinator: NSObject, TerminalViewDelegate {
        let model: SessionDetailModel
        init(model: SessionDetailModel) { self.model = model }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let s = String(decoding: data, as: UTF8.self)
            Task { await model.sendKeys(s) }
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { model.resize(cols: newCols, rows: newRows) }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}  // T-03-20
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}  // T-03-19
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities { [] }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

struct ExtraKeysBar: View {
    let model: SessionDetailModel
    private let keys: [(label: String, spoken: String, seq: String)] = [
        ("Esc", "Escape", "\u{1b}"), ("Tab", "Tab", "\t"), ("Ctrl-C", "Control C", "\u{03}"),
        ("↑", "Up arrow", "\u{1b}[A"), ("↓", "Down arrow", "\u{1b}[B"),
        ("←", "Left arrow", "\u{1b}[D"), ("→", "Right arrow", "\u{1b}[C"), ("Enter", "Return", "\r"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(keys, id: \.label) { k in
                    Button { Haptics.toggle(); Task { await model.sendKeys(k.seq) } } label: {
                        Text(k.label)
                            .font(Typography.mono.weight(.medium)).foregroundStyle(Palette.ink)
                            .padding(.horizontal, Spacing.m).frame(minWidth: 44, minHeight: 44)
                            .background(Palette.paper, in: .rect(cornerRadius: Spacing.cornerSmall, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.75))
                            .shadow(color: Palette.ink.opacity(0.10), radius: 0, x: 0, y: 1.5)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel(k.spoken)
                }
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        }
        .background(Palette.surfaceAlt)
        .overlay(alignment: .top) { Palette.divider.frame(height: 0.5) }
    }
}

/// Terminal inside a paper card (paper by default, warm ink when the dark toggle is on).
struct TerminalCard: View {
    let model: SessionDetailModel
    @AppStorage("terminalDark") private var terminalDark = false

    var body: some View {
        Card(padding: Spacing.s) {
            TerminalScreen(model: model)
                .background(terminalDark ? Palette.ink : Palette.paper)
                .clipShape(.rect(cornerRadius: Spacing.cornerMedium, style: .continuous))
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .safeAreaInset(edge: .bottom) { ExtraKeysBar(model: model) }
    }
}
