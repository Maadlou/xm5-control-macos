import XCTest

final class AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimarySurfaceAppears() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        #if MENU_BAR_APP
        app.launchArguments.append("--ui-test-host")
        #endif
        app.launch()

        #if MENU_BAR_APP
        XCTAssertTrue(app.otherElements["headphones.dashboard"].waitForExistence(timeout: 5))
        #else
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 5))
        #endif
    }

    #if MENU_BAR_APP || HYBRID_APP
    @MainActor
    func testMenuBarContentAppearsInDebugHost() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.otherElements["headphones.dashboard"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomEqualizerEditorAndPresetSaving() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.otherElements["headphones.dashboard"].waitForExistence(timeout: 5))
        app.menuButtons["equalizer.preset"].click()
        app.menuItems["Custom Equalizer…"].click()

        let editor = app.otherElements["equalizer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.sliders.count, 6)
        XCTAssertTrue(editor.buttons["Reset Flat"].exists)

        let name = editor.textFields["Preset name"]
        name.click()
        name.typeText("Cinema")
        editor.buttons["Save"].click()
        XCTAssertTrue(editor.buttons["Cinema"].waitForExistence(timeout: 2))
    }
    #endif
}
