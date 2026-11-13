import SwiftUI

/// Slim paper strip above the session list. Hidden while the hub is healthy;
/// amber after 45 s of silence, red when unreachable. Tap to retry.
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
                bannerView(text: "Hub quiet for \(secondsAgoText)", color: Palette.warning)
            case .red(let reason):
                bannerView(text: reason, color: Palette.danger)
            }
        }
        .onReceive(ticker) { now = $0 }
        .motion(Motion.gentle, value: tone)
    }

    private enum Tone: Equatable {
        case healthy
        case amber
        case red(String)
    }

    private var tone: Tone {
        if app.demoMode { return .healthy }
        switch app.connectionState {
        case .unreachable(let r): return .red("Can't reach hub: \(r.prefix(60))")
        case .unknown: return .amber
        case .healthy:
            guard let last = app.lastSuccessfulCall else { return .amber }
            let age = now.timeIntervalSince(last)
            if age > 120 { return .red("No contact with hub for \(Int(age)) s") }
            if age > 45 { return .amber }
            return .healthy
        }
    }

    private var secondsAgoText: String {
        guard let last = app.lastSuccessfulCall else { return "a moment" }
        return "\(Int(now.timeIntervalSince(last))) s"
    }

    private func bannerView(text: String, color: Color) -> some View {
        Button {
            Haptics.toggle()
            Task { await app.bootstrap() }
        } label: {
            HStack(spacing: Spacing.m) {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(text)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Retry")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Palette.primaryDeep)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .frame(minHeight: 44)
            .background(Palette.paper)
            .overlay(alignment: .bottom) {
                Rectangle().fill(color.opacity(0.5)).frame(height: 1)
            }
        }
        .buttonStyle(PressableStyle(scale: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel(text)
        .accessibilityHint("Retries the connection")
    }
}
