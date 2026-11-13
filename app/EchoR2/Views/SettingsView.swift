import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false
    @State private var sending = false
    @State private var testResult: String?

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
                        Eyebrow(text: "Notifications")
                        row("Permission", app.pushAuthorized.map { $0 ? "allowed" : "off" } ?? "not asked")
                        row("Hub push", app.health?.push ?? "unknown")
                        row("Registered", app.pushRegistered ? "yes" : "no")
                        if let e = app.health?.pushLastError {
                            Text("Last push error: \(e.message)").font(Typography.callout).foregroundStyle(Palette.danger)
                                .accessibilityIdentifier("settings.push.lasterror")
                        }
                        if let e = app.pushError {
                            Text(e).font(Typography.callout).foregroundStyle(Palette.danger)
                        }
                        SecondaryButton(title: "Send test push") { Task { await sendTest() } }
                            .disabled(sending)
                            .accessibilityIdentifier("settings.push.test")
                        if let r = testResult {
                            Text(r).font(Typography.callout).foregroundStyle(Palette.textSecondary)
                                .accessibilityIdentifier("settings.push.result")
                        }
                        if app.pushAuthorized == false {
                            SecondaryButton(title: "Open iOS Settings") {
                                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                            }
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

    private func sendTest() async {
        guard let c = app.client() else { return }
        sending = true
        defer { sending = false }
        do {
            let r = try await c.testPush()
            if let f = r.results.first(where: { $0.status != 200 }) {
                testResult = f.message ?? f.reason ?? "Push failed (\(f.status))"
                Haptics.error()
            } else {
                testResult = "Sent. Check your lock screen."
                Haptics.success()
            }
            await app.bootstrap()
        } catch HubError.server("push_unconfigured", _) {
            testResult = "Hub has no APNs key yet"
        } catch HubError.server("no_token", _) {
            testResult = "This phone has no push token on the hub yet"
        } catch {
            app.handle(error)
            testResult = "Test push failed"
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
