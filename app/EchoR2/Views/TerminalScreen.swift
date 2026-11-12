import SwiftTerm
import SwiftUI

/// Embeds the model-owned TerminalView (never recreated, so scrollback persists).
struct TerminalScreen: UIViewRepresentable {
    let model: SessionDetailModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> TerminalView {
        model.terminal.terminalDelegate = context.coordinator
        return model.terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

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
    private let keys: [(String, String)] = [
        ("Esc", "\u{1b}"), ("Tab", "\t"), ("Ctrl-C", "\u{03}"),
        ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("←", "\u{1b}[D"), ("→", "\u{1b}[C"), ("Enter", "\r"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(keys, id: \.0) { k in
                    Button(k.0) { Task { await model.sendKeys(k.1) } }
                        .font(Typography.mono).foregroundStyle(Palette.ink)
                        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                        .background(Palette.paper, in: Capsule())
                        .overlay(Capsule().stroke(Palette.border, lineWidth: 0.75))
                }
            }
            .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
        }
    }
}

/// Dark terminal inside a paper card; extra keys ride above the keyboard.
struct TerminalCard: View {
    let model: SessionDetailModel

    var body: some View {
        Card(padding: Spacing.s) {
            TerminalScreen(model: model)
                .background(Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium))
        }
        .padding(Spacing.m)
        .safeAreaInset(edge: .bottom) { ExtraKeysBar(model: model).background(Palette.paper) }
    }
}
