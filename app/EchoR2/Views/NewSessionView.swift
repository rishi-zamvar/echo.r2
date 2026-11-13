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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    GroupTitle(text: "Folder")
                    folders.motion(Motion.gentle, value: roots == nil)

                    GroupTitle(text: "First prompt").padding(.top, Spacing.l)
                    promptCard

                    PrimaryButton(title: "Start session", action: { Task { await start() } },
                                  isLoading: starting, icon: "sparkles")
                        .disabled(selectedCwd == nil || starting)
                        .padding(.top, Spacing.l)
                        .accessibilityHint(selectedCwd == nil ? "Choose a folder first" : "Starts Claude in the chosen folder")
                }
                .padding(Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await load() }
            .wcoachToasts()
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var folders: some View {
        if let roots {
            ForEach(roots, id: \.root) { r in
                Card(padding: 0) {
                    ForEach(Array(r.cwdOptions.enumerated()), id: \.element) { i, cwd in
                        if i > 0 { Rectangle().fill(Palette.divider).frame(height: 0.75).padding(.leading, 52) }
                        folderRow(cwd, name: i == 0 ? (r.root as NSString).lastPathComponent : (cwd as NSString).lastPathComponent,
                                  isRoot: i == 0)
                    }
                }
            }
        } else if loadFailed {
            Card {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Label("Can't load folders from the hub.", systemImage: "exclamationmark.triangle")
                        .font(Typography.callout).foregroundStyle(Palette.danger)
                    SecondaryButton(title: "Try again") { Task { await load() } }
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: Spacing.m) { SkeletonRow(); SkeletonRow() }
                .accessibilityElement()
                .accessibilityLabel("Loading folders")
        }
    }

    private func folderRow(_ cwd: String, name: String, isRoot: Bool) -> some View {
        let selected = selectedCwd == cwd
        return Button {
            Haptics.toggle()
            Motion.animate(Motion.snappy) { selectedCwd = cwd }
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: selected ? "folder.fill" : "folder")
                    .font(Typography.body)
                    .foregroundStyle(selected ? Palette.primaryDeep : Palette.textMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRoot ? "\(name) (whole folder)" : name)
                        .font(Typography.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Palette.ink)
                    if isRoot {
                        Text(cwd).font(Typography.caption.monospaced()).foregroundStyle(Palette.textMuted)
                    }
                }
                Spacer(minLength: Spacing.s)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.primaryDeep)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .frame(minHeight: 52)
            .background(selected ? Palette.primary.opacity(0.14) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRoot ? "\(name), whole folder" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var promptCard: some View {
        Card(padding: Spacing.m) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Optional. What should Claude start on?")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $prompt)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .accessibilityLabel("First prompt, optional")
                    .onChange(of: prompt) { _, v in
                        if v.count > Self.maxPrompt { prompt = String(v.prefix(Self.maxPrompt)) }
                    }
            }
        }
    }

    private func load() async {
        guard let c = app.client() else { return }
        loadFailed = false
        do { roots = try await c.roots().roots }
        catch { app.handle(error); loadFailed = true; Haptics.failure() }
    }

    private func start() async {
        guard let cwd = selectedCwd, let c = app.client() else { return }
        Haptics.send()
        starting = true
        defer { starting = false }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try await c.createSession(cwd: cwd, prompt: trimmed.isEmpty ? nil : trimmed)
            await app.refreshSessions()
            dismiss()
            onCreated(id)
        } catch HubError.server("bad_cwd", _) {
            ToastCenter.shared.show("That folder isn't allowed on the hub", kind: .error)
        } catch HubError.server("claude_unavailable", _) {
            ToastCenter.shared.show("Claude isn't available on the hub", kind: .error)
        } catch HubError.server("spawn_failed", _) {
            ToastCenter.shared.show("Couldn't start Claude", kind: .error)
        } catch {
            app.handle(error)
            ToastCenter.shared.show("Can't reach the hub", kind: .error)
        }
    }
}
