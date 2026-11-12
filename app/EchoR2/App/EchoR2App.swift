import SwiftUI

@main
struct EchoR2App: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            BackgroundAtmosphere().ignoresSafeArea()
            // 03-02 swaps the paired root to the Sessions list, Settings behind a gear.
            if app.isPaired { SettingsView() } else { PairingView() }
        }
    }
}
