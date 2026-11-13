import SwiftUI
import UIKit

struct PairingView: View {
    @Environment(AppModel.self) private var app
    @State private var host = ""
    @State private var code = ""
    @State private var info: Result<Health, HubError>?
    @State private var pairing = false
    @State private var error: String?
    @State private var autoRunning = false
    @State private var autoStatus: String?

    private var canPair: Bool {
        HubClient.baseURL(from: host) != nil && code.count == 8 && !pairing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AppMark().padding(.top, Spacing.xxl)

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GroupTitle(text: "Hub")
                        TextField("host:8790", text: $host)
                            .font(Typography.mono)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .accessibilityIdentifier("pair.host")
                        hubInfo
                    }
                }

                if autoRunning {
                    HStack(spacing: Spacing.m) {
                        ProgressView()
                        Text("Pairing automatically…").font(Typography.callout)
                    }
                    .accessibilityIdentifier("pair.auto.status")
                } else if app.autoPairTried {
                    if let autoStatus {
                        Text(autoStatus).font(Typography.callout).foregroundStyle(Palette.textSecondary)
                            .accessibilityIdentifier("pair.auto.status")
                    }
                    codeFields
                }
            }
            .padding(Spacing.l)
        }
        .onAppear { if host.isEmpty { host = app.host } }
        .task { await runAutoPair() }
        // Re-runs (and cancels the previous run) on every host edit; sleep = debounce.
        .task(id: host) {
            info = nil
            guard HubClient.baseURL(from: host) != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let r = await app.checkHealth(host: host)
            if !Task.isCancelled { info = r }
        }
    }

    private func runAutoPair() async {
        guard !app.autoPairTried, HubClient.baseURL(from: app.host) != nil else { return }
        autoRunning = true
        let r = await app.autoPair(deviceName: UIDevice.current.name)
        autoRunning = false
        switch r {
        case .paired: break
        case .refused(let c):
            autoStatus = c == "auto_pair_denied" ? "This device isn't allowed to pair automatically"
                                                 : "Enter a code from `hub pair`"
            Haptics.failure()
        case .unreachable:
            autoStatus = "Can't reach hub. Enter a code from `hub pair`"
            Haptics.failure()
        }
    }

    @ViewBuilder private var codeFields: some View {
        VStack(spacing: Spacing.xl) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        GroupTitle(text: "Pairing code")
                        TextField("8 characters", text: $code)
                            .font(Typography.mono)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("pair.code")
                            .onChange(of: code) { _, new in
                                let t = PairingCode.normalize(new)
                                if t != new { code = t }
                            }
                        if let error {
                            Text(error).font(Typography.callout).foregroundStyle(Palette.danger)
                        }
                    }
                }

                PrimaryButton(title: "Pair", action: pair, isLoading: pairing)
                    .disabled(!canPair)
                    .opacity(canPair ? 1 : 0.5)
                    .accessibilityIdentifier("pair.submit")
        }
    }

    @ViewBuilder private var hubInfo: some View {
        switch info {
        case .success(let h):
            Text("\(h.hubName) · \(h.os) · \(h.gitSha)")
                .font(Typography.caption).foregroundStyle(Palette.primaryDeep)
        case .failure:
            Text("Can't reach hub").font(Typography.caption).foregroundStyle(Palette.danger)
        case nil:
            EmptyView()
        }
    }

    private func pair() {
        pairing = true
        error = nil
        Task {
            defer { pairing = false }
            do {
                try await app.pair(host: host, code: code, deviceName: UIDevice.current.name)
            } catch HubError.server("bad_code", _) {
                error = "Wrong or expired code. Get a new one."
                Haptics.failure()
            } catch HubError.forbidden {
                error = "Hub refused this device"
            } catch {
                self.error = "Can't reach hub"
                Haptics.failure()
            }
        }
    }
}
