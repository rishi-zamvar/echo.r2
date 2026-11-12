import SwiftUI

/// Slim status strip pinned to the top of MainTabView. Stays out of the way
/// when connection is healthy; pulses amber after 45s of silence, red after
/// 2 minutes. Tap to retry.
struct ConnectionBanner: View {
    @Environment(AppModel.self) private var app
    @State private var now: Date = Date()

    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch tone {
            case .healthy:
                EmptyView()
            case .amber:
                bannerView(text: "Backend quiet for \(secondsAgoText)", color: Palette.warning)
                    .transition(.move(edge: .top).combined(with: .opacity))
            case .red(let reason):
                bannerView(text: reason, color: Palette.danger)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(ticker) { now = $0 }
        .animation(AnimationToken.medium, value: tone)
    }

    private enum Tone: Equatable {
        case healthy
        case amber
        case red(String)
    }

    private var tone: Tone {
        if app.demoMode { return .healthy }
        switch app.connectionState {
        case .unreachable(let r): return .red("Offline — \(r.prefix(40))")
        case .unknown: return .amber
        case .healthy:
            guard let last = app.lastSuccessfulCall else { return .amber }
            let age = now.timeIntervalSince(last)
            if age > 120 { return .red("No backend contact for \(Int(age))s") }
            if age > 45  { return .amber }
            return .healthy
        }
    }

    private var secondsAgoText: String {
        guard let last = app.lastSuccessfulCall else { return "—" }
        let age = Int(now.timeIntervalSince(last))
        return "\(age)s"
    }

    private func bannerView(text: String, color: Color) -> some View {
        Button {
            Haptics.light()
            Task { await app.bootstrap() }
        } label: {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(text)
                    .font(Typography.caption)
                    .tracking(0.3)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("Retry")
                    .eyebrowStyle(color)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.18))
            .overlay(alignment: .bottom) {
                Rectangle().fill(color.opacity(0.35)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}
