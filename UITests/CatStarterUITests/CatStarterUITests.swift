import XCTest

@MainActor
final class CatStarterUITests: XCTestCase {
    func testCatObservesScreenWithoutAButton() {
        let app = launchApp()
        defer { app.terminate() }
        let observation = app.staticTexts["screen-observation"]

        XCTAssertTrue(observation.waitForExistence(timeout: 5))
        let recognized = NSPredicate(format: "label == %@", "Вижу: HELLO FROM THE SCREEN")
        expectation(for: recognized, evaluatedWith: observation)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["Посмотреть экран"].exists)
    }

    func testCatChangesPositionByItself() {
        let app = launchApp()
        defer { app.terminate() }
        let canvas = app.descendants(matching: .any)["cat-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let initialPosition = canvas.value as? String

        let moved = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let value = element.value as? String
            else {
                return false
            }
            return value != initialPosition
        }
        expectation(for: moved, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["CAT_STARTER_UI_TEST_OCR_TEXT"] = "HELLO FROM THE SCREEN"
        app.launch()

        XCTAssertTrue(app.windows["Cat Starter"].waitForExistence(timeout: 5))
        return app
    }
}
