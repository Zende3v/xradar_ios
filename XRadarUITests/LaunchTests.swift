import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A fresh install has not answered the location question: the app opens on the location screen.
    @MainActor
    func testFreshInstallOpensOnTheLocationScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.permission"].waitForExistence(timeout: 10))
    }
}
