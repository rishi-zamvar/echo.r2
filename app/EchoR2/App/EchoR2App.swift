import SwiftUI
import SwiftTerm

struct TermProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> TerminalView { TerminalView(frame: .zero) }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
}

@main
struct EchoR2App: App {
    var body: some Scene { WindowGroup { TermProbe() } }
}
