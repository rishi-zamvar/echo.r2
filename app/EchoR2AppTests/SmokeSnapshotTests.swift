import SwiftUI
import XCTest
@testable import EchoR2

@MainActor
final class SmokeSnapshotTests: XCTestCase {
    func testSessionsList() {
        snap(ZStack { BackgroundAtmosphere().ignoresSafeArea(); NavigationStack { SessionsListView() } },
             named: "light")
    }
}
