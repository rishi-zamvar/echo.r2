import SwiftUI
import UIKit

@main
struct EchoR2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { Self.styleNavigationBars() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.app)
                .tint(Palette.primaryDeep)
        }
    }

    /// Serif ink titles (DESIGN.md "Type"). SwiftUI has no title-font API, so this is
    /// the one UIKit appearance hook; bar backgrounds stay system (transparent at rest).
    private static func styleNavigationBars() {
        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let d = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return UIFont(descriptor: d.withDesign(.serif) ?? d, size: 0)
        }
        let ink = UIColor(Palette.ink)
        let large: [NSAttributedString.Key: Any] = [.font: serif(.largeTitle, .regular), .foregroundColor: ink]
        let inline: [NSAttributedString.Key: Any] = [.font: serif(.headline, .semibold), .foregroundColor: ink]
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        for a in [edge, standard] { a.largeTitleTextAttributes = large; a.titleTextAttributes = inline }
        let bar = UINavigationBar.appearance()
        bar.scrollEdgeAppearance = edge
        bar.compactScrollEdgeAppearance = edge
        bar.standardAppearance = standard
        bar.compactAppearance = standard
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            BackgroundAtmosphere()
            if app.isPaired {
                VStack(spacing: 0) {
                    ConnectionBanner()
                    NavigationStack(path: $app.path) { SessionsListView() }
                }
                .transition(.opacity)
            } else {
                PairingView().transition(.opacity)
            }
        }
        .motion(Motion.gentle, value: app.isPaired)
        .task(id: app.isPaired) { if app.isPaired { await PushSetup.enable(app) } }
        .onChange(of: scenePhase) { _, p in
            if p == .active, app.isPaired { Task { await app.bootstrap() } }
        }
    }
}
