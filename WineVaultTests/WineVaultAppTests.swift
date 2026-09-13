import XCTest
@testable import WineVault

/// App-target smoke test for the issue #1 skeleton: proves the app host
/// builds, the placeholder root view exists, and unit tests can run in it.
final class WineVaultAppTests: XCTestCase {
    func testContentViewInstantiates() {
        _ = ContentView()  // must not crash at init
    }
}
