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
                AppMark()
                    .padding(.top, Spacing.xxxl)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("echo")
                    .accessibilityAddTraits(.isHeader)

                Text("Connect this phone to the hub on your home PC.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)

                if autoRunning {
                    Card {
                        HStack(spacing: Spacing.m) {
                            ProgressView().tint(Palette.primaryDeep)
                            Text("Pairing with your hub…").font(Typography.body).foregroundStyle(Palette.ink)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pair.auto.status")
                    .transition(.opacity)
                } else {
                    hubCard.transition(.opacity)
                    if app.autoPairTried { codeFields.transition(.opacity.combined(with: .move(edge: .bottom))) }
                }
            }
            .padding(Spacing.l)
            .motion(Motion.gentle, value: autoRunning)
            .motion(Motion.gentle, value: app.autoPairTried)
        }
        .scrollDismissesKeyboard(.interactively)
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
            autoStatus = c == "auto_pair_denied" ? "This device isn't allowed to pair automatically. Use a code instead."
                                                 : "Automatic pairing didn't work. Use a code instead."
            Haptics.failure()
        case .unreachable:
            autoStatus = "Can't reach the hub automatically. Use a code instead."
            Haptics.failure()
        }
    }

    private var hubCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.s) {
                fieldLabel("Hub address")
                TextField("host:8790", text: $host, prompt: Text("host:8790").foregroundStyle(Palette.textMuted))
                    .font(Typography.mono)
                    .foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Hub address")
                    .accessibilityIdentifier("pair.host")
                hubInfo
            }
        }
    }

    private var codeFields: some View {
        VStack(spacing: Spacing.l) {
            if let autoStatus {
                Label(autoStatus, systemImage: "info.circle")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("pair.auto.status")
            }
            Card {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    fieldLabel("Pairing code")
                    TextField("8 characters", text: $code, prompt: Text("8 characters").foregroundStyle(Palette.textMuted))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                        .accessibilityLabel("Pairing code")
                        .accessibilityIdentifier("pair.code")
                        .onChange(of: code) { _, new in
                            let t = PairingCode.normalize(new)
                            if t != new { code = t }
                        }
                    Text("Run `hub pair` on the hub to get one.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textMuted)
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.danger)
                            .transition(.opacity)
                    }
                }
                .motion(Motion.snappy, value: error)
            }
            PrimaryButton(title: "Pair", action: pair, isLoading: pairing)
                .disabled(!canPair)
                .accessibilityIdentifier("pair.submit")
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(Typography.callout.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var hubInfo: some View {
        switch info {
        case .success(let h):
            status("Found \(h.hubName) · \(h.os)", color: Palette.running)
        case .failure:
            status("Can't reach this address", color: Palette.danger)
        case nil:
            EmptyView()
        }
    }

    private func status(_ text: String, color: Color) -> some View {
        HStack(spacing: Spacing.s) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(Typography.caption).foregroundStyle(color)
        }
        .transition(.opacity)
    }

    private func pair() {
        pairing = true
        error = nil
        Task {
            defer { pairing = false }
            do {
                try await app.pair(host: host, code: code, deviceName: UIDevice.current.name)
            } catch HubError.server("bad_code", _) {
                error = "Wrong or expired code. Run “hub pair” for a new one."
                Haptics.failure()
            } catch HubError.forbidden {
                error = "The hub refused this device."
                Haptics.failure()
            } catch {
                self.error = "Can't reach the hub. Check the address and Tailscale."
                Haptics.failure()
            }
        }
    }
}
