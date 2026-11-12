import SwiftUI

@main
struct EchoR2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            BackgroundAtmosphere().ignoresSafeArea()
            if app.isPaired {
                VStack(spacing: 0) {
                    ConnectionBanner()
                    NavigationStack(path: $app.path) { SessionsListView() }
                }
            } else { PairingView() }
        }
        .task(id: app.isPaired) { if app.isPaired { await PushSetup.enable(app) } }
        .onChange(of: scenePhase) { _, p in
            if p == .active, app.isPaired { Task { await app.bootstrap() } }
        }
    }
}
