import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false
    @State private var sending = false
    @State private var testResult: (text: String, ok: Bool)?

    private var appVersion: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    private var hubRows: [(String, String)] {
        var r = [("Address", app.host)]
        if let h = app.health {
            r += [("Name", h.hubName), ("OS", h.os), ("Build", h.gitSha),
                  ("Protocol", String(h.protocolVersion)), ("Claude", h.claude?.version ?? "unavailable")]
        }
        return r
    }

    private var pushRows: [(String, String)] {
        [("Permission", app.pushAuthorized.map { $0 ? "Allowed" : "Off" } ?? "Not asked"),
         ("Hub push", (app.health?.push ?? "unknown").capitalized),
         ("This phone", app.pushRegistered ? "Registered" : "Not registered")]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                GroupTitle(text: "Hub")
                Card {
                    rows(hubRows)
                    if app.health == nil, case .unreachable(let r) = app.connectionState {
                        note(r, systemImage: "wifi.exclamationmark", color: Palette.danger)
                    }
                }

                GroupTitle(text: "Notifications").padding(.top, Spacing.l)
                Card {
                    rows(pushRows)
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        if let e = app.health?.pushLastError {
                            note("Last push error: \(e.message)", systemImage: "exclamationmark.triangle", color: Palette.danger)
                                .accessibilityIdentifier("settings.push.lasterror")
                        }
                        if let e = app.pushError {
                            note(e, systemImage: "exclamationmark.triangle", color: Palette.danger)
                        }
                        SecondaryButton(title: sending ? "Sending…" : "Send test push") {
                            Task { await sendTest() }
                        }
                        .disabled(sending)
                        .accessibilityIdentifier("settings.push.test")
                        if let r = testResult {
                            Text(r.text)
                                .font(Typography.callout)
                                .foregroundStyle(r.ok ? Palette.running : Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                                .accessibilityIdentifier("settings.push.result")
                        }
                        if app.pushAuthorized == false {
                            SecondaryButton(title: "Open iOS Settings") {
                                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                            }
                        }
                    }
                    .padding(.top, Spacing.m)
                    .motion(Motion.gentle, value: testResult?.text)
                }

                GroupTitle(text: "App").padding(.top, Spacing.l)
                Card { rows([("Version", appVersion)]) }

                SecondaryButton(title: "Forget hub", destructive: true) {
                    Haptics.destructive()
                    confirmForget = true
                }
                .padding(.top, Spacing.xl)
                .accessibilityHint("Unpairs this phone. You'll need a new code to reconnect.")
            }
            .padding(Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.bootstrap() }
        .confirmationDialog("Forget this hub?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget hub", role: .destructive) { app.forget() }
        } message: {
            Text("This phone stops receiving updates until you pair again.")
        }
    }

    private func rows(_ items: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(Palette.divider).frame(height: 0.75) }
                LabeledRow(label: item.0, value: item.1)
            }
        }
    }

    private func note(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(Typography.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sendTest() async {
        guard let c = app.client() else { return }
        sending = true
        defer { sending = false }
        do {
            let r = try await c.testPush()
            if let f = r.results.first(where: { $0.status != 200 }) {
                testResult = (f.message ?? f.reason ?? "Push failed (\(f.status))", false)
                Haptics.failure()
            } else {
                testResult = ("Sent. Check your lock screen.", true)
                Haptics.paired()
            }
            await app.bootstrap()
        } catch HubError.server("push_unconfigured", _) {
            testResult = ("The hub has no APNs key yet.", false)
            Haptics.failure()
        } catch HubError.server("no_token", _) {
            testResult = ("This phone has no push token on the hub yet.", false)
            Haptics.failure()
        } catch {
            app.handle(error)
            testResult = ("Test push failed. Can't reach the hub.", false)
            Haptics.failure()
        }
    }
}
