import XCTest

let HUB_RUNNING = "aaaaaaaa-0000-4000-8000-000000000001"
let HUB_STOPPED = "aaaaaaaa-0000-4000-8000-000000000002"
let EXT_EVEN = "aaaaaaaa-0000-4000-8000-000000000003"
let EXT_CLI = "aaaaaaaa-0000-4000-8000-000000000004"
let NOISE_P = "aaaaaaaa-0000-4000-8000-000000000005"
let NOISE_OLD = "aaaaaaaa-0000-4000-8000-000000000006"

@MainActor
func launchApp(_ extra: [String] = [], token: String? = "mock-token") -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["-uiTestReset", "-uiTestHubHost", "127.0.0.1:8799"]
    if let token { args += ["-uiTestToken", token] }
    app.launchArguments = args + extra
    app.launch()
    return app
}

/// Synchronously POSTs scenario settings to the mock hub (e.g. ["autoPair": "deny"]).
func mockScenario(_ json: [String: String]) {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:8799/__scenario")!)
    req.httpMethod = "POST"
    req.httpBody = try? JSONEncoder().encode(json)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
    _ = done.wait(timeout: .now() + 5)
}
