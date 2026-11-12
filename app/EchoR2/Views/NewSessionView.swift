import SwiftUI

struct NewSessionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void

    @State private var roots: [Root]?
    @State private var loadFailed = false
    @State private var selectedCwd: String?
    @State private var prompt = ""
    @State private var starting = false

    private static let maxPrompt = 10_000

    var body: some View {
        NavigationStack {
            Form {
                if let roots {
                    ForEach(roots, id: \.root) { r in
                        Section {
                            ForEach(Array(r.cwdOptions.enumerated()), id: \.element) { i, cwd in
                                Button {
                                    selectedCwd = cwd
                                } label: {
                                    HStack {
                                        Text(i == 0 ? "(this folder)" : (cwd as NSString).lastPathComponent)
                                            .foregroundStyle(Palette.ink)
                                        Spacer()
                                        if selectedCwd == cwd { Image(systemName: "checkmark").foregroundStyle(Palette.primaryDeep) }
                                    }
                                }
                            }
                        } header: {
                            Text(r.root).font(Typography.caption.monospaced())
                        }
                    }
                } else if loadFailed {
                    VStack(spacing: Spacing.m) {
                        Text("Can't load folders").foregroundStyle(Palette.danger)
                        SecondaryButton(title: "Retry") { Task { await load() } }
                    }
                } else {
                    ProgressView()
                }

                Section("First prompt (optional)") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 100)
                        .onChange(of: prompt) { _, v in
                            if v.count > Self.maxPrompt { prompt = String(v.prefix(Self.maxPrompt)) }
                        }
                }

                Section {
                    PrimaryButton(title: "Start", action: { Task { await start() } }, isLoading: starting)
                        .disabled(selectedCwd == nil || starting)
                        .opacity(selectedCwd == nil ? 0.5 : 1)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await load() }
            .wcoachToasts()
        }
    }

    private func load() async {
        guard let c = app.client() else { return }
        loadFailed = false
        do { roots = try await c.roots().roots }
        catch { app.handle(error); loadFailed = true }
    }

    private func start() async {
        guard let cwd = selectedCwd, let c = app.client() else { return }
        starting = true
        defer { starting = false }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try await c.createSession(cwd: cwd, prompt: trimmed.isEmpty ? nil : trimmed)
            await app.refreshSessions()
            dismiss()
            onCreated(id)
        } catch HubError.server("bad_cwd", _) {
            ToastCenter.shared.show("Folder not allowed", kind: .error)
        } catch HubError.server("claude_unavailable", _) {
            ToastCenter.shared.show("Claude not available on hub", kind: .error)
        } catch HubError.server("spawn_failed", _) {
            ToastCenter.shared.show("Couldn't start Claude", kind: .error)
        } catch {
            app.handle(error)
            ToastCenter.shared.show("Can't reach hub", kind: .error)
        }
    }
}
