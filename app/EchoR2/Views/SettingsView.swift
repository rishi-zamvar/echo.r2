import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false

    private var appVersion: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AppMark().padding(.top, Spacing.xxl)

                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Eyebrow(text: "Hub")
                        row("Host", app.host)
                        if let h = app.health {
                            row("Name", h.hubName)
                            row("OS", h.os)
                            row("Build", h.gitSha)
                            row("Protocol", String(h.protocolVersion))
                            row("Claude", h.claude?.version ?? "unavailable")
                        } else if case .unreachable(let r) = app.connectionState {
                            Text(r).font(Typography.callout).foregroundStyle(Palette.danger)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Eyebrow(text: "App")
                        row("Version", appVersion)
                    }
                }

                SecondaryButton(title: "Forget hub") { confirmForget = true }
            }
            .padding(Spacing.l)
        }
        .task { await app.bootstrap() }
        .confirmationDialog("Forget this hub?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget hub", role: .destructive) { app.forget() }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Typography.callout).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(v).font(Typography.mono).foregroundStyle(Palette.ink)
        }
    }
}
