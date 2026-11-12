import SwiftUI
import UIKit
import XCTest
import SnapshotTesting
@testable import EchoR2

private final class BundleAnchor {}

@MainActor
func snap<V: View>(_ view: V, named: String, xxl: Bool = false, model: AppModel? = nil,
                   file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
    let vc = UIHostingController(rootView: view.environment(model ?? fixtureModel()))
    let traits = UITraitCollection(preferredContentSizeCategory: xxl ? .extraExtraLarge : .large)
    let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    withSnapshotTesting(record: record ? .all : .missing) {
        assertSnapshot(of: vc,
                       as: .image(on: .iPhone13Pro, precision: 0.99, perceptualPrecision: 0.98, traits: traits),
                       named: named, file: file, testName: testName, line: line)
    }
}

/// Fixture-seeded model: no network, demo mode.
@MainActor
func fixtureModel() -> AppModel {
    let app = AppModel()
    let url = Bundle(for: BundleAnchor.self).url(forResource: "sessions", withExtension: "json")!
    let r = try! JSONDecoder().decode(SessionsResponse.self, from: Data(contentsOf: url))
    app.sessions = r.sessions
    app.demoMode = true
    app.sessionsLoaded = true
    return app
}
