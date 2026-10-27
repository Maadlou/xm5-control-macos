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
        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 5))
        #else
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 5))
        #endif
    }

    @MainActor
    private func launchScenario(_ model: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "--ui-test-host", "--ui-test-model", model,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }
    @MainActor
    private func openEditor(_ app: XCUIApplication) -> XCUIElement {
        let menu = app.descendants(matching: .any)["equalizer.preset"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        app.menuItems["Custom Equalizer…"].click()
        let editor = app.descendants(matching: .any)["equalizer.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        return editor
    }
    @MainActor
    func testXM6EditorUsesTenBandsAndNativePresets() {
        let app = launchScenario("xm6")
        let menu = app.descendants(matching: .any)["equalizer.preset"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        XCTAssertTrue(app.menuItems["Heavy"].exists)
        XCTAssertFalse(app.menuItems["Bright"].exists)
        app.menuItems["Custom Equalizer…"].click()
        let editor = app.descendants(matching: .any)["equalizer.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.sliders.count, 10)
        XCTAssertTrue(editor.sliders["equalizer.band.xm6TenBand.0"].exists)
        XCTAssertTrue(editor.sliders["equalizer.band.xm6TenBand.9"].exists)
        XCTAssertFalse(editor.sliders["Clear Bass"].exists)
        editor.buttons["Reset Flat"].click()
        XCTAssertTrue(editor.staticTexts["Synced"].waitForExistence(timeout: 5))
        let lastBand = editor.sliders["equalizer.band.xm6TenBand.9"]
        editor.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -260)
        XCTAssertTrue(lastBand.isHittable)
        lastBand.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertEqual((lastBand.value as? NSNumber)?.intValue, 6)
    }
    @MainActor
    func testMainPresetMenuShowsOnlyCompatibleProfiles() {
        let app = launchScenario("xm6", extra: ["--ui-test-seed-profiles"])
        let menu = app.descendants(matching: .any)["equalizer.preset"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        app.menuItems["Mac Presets"].click()
        XCTAssertTrue(app.menuItems["XM6 only"].exists)
        XCTAssertFalse(app.menuItems["XM5 only"].exists)
    }
    @MainActor
    func testUnsupportedEQLeavesNoiseControlsAvailable() {
        let app = launchScenario("xm6-no-eq")
        XCTAssertTrue(app.buttons["ANC"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ANC"].isEnabled)
        let menu = app.descendants(matching: .any)["equalizer.preset"].firstMatch
        XCTAssertTrue(menu.exists)
        XCTAssertFalse(menu.isEnabled)
        app.buttons["ANC"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Noise cancellation on"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor
    func testOfflineEditingAndSaving() {
        let app = launchScenario("disconnected-xm5")
        let open = app.buttons["Edit saved equalizer…"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        let editor = app.descendants(matching: .any)["equalizer.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.sliders.count, 6)
        editor.buttons["Reset Flat"].click()
        editor.textFields["Preset name"].click()
        editor.textFields["Preset name"].typeText("Offline")
        editor.buttons["Save"].click()
        XCTAssertTrue(editor.buttons["Offline"].waitForExistence(timeout: 2))
        XCTAssertTrue(editor.staticTexts["Offline editing"].exists)
    }
    @MainActor
    func testSwitchingModelsWhileEditorOpenReplacesLayoutAndProfiles() {
        let app = launchScenario("xm6", extra: ["--ui-test-seed-profiles"])
        let editor = openEditor(app)
        XCTAssertEqual(editor.sliders.count, 10)
        XCTAssertTrue(editor.buttons["XM6 only"].exists)
        XCTAssertFalse(editor.buttons["XM5 only"].exists)
        editor.buttons["simulation.switch.xm5"].click()
        let first = editor.sliders["equalizer.band.xm5SixValue.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.sliders.count, 6)
        XCTAssertTrue(editor.buttons["XM5 only"].exists)
        XCTAssertFalse(editor.buttons["XM6 only"].exists)
        XCTAssertTrue(editor.sliders["Clear Bass"].exists)
        editor.buttons["simulation.switch.xm6"].click()
        XCTAssertTrue(editor.sliders["equalizer.band.xm6TenBand.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.sliders.count, 10)
        XCTAssertTrue(editor.buttons["XM6 only"].exists)
        XCTAssertFalse(editor.buttons["XM5 only"].exists)
    }
    @MainActor
    func testRejectedWriteShowsFailureInsteadOfSynced() {
        let app = launchScenario("xm6-reject-writes")
        let editor = openEditor(app)
        editor.buttons["Reset Flat"].click()
        XCTAssertTrue(editor.staticTexts["Not confirmed"].waitForExistence(timeout: 6))
        XCTAssertFalse(editor.staticTexts["Synced"].exists)
    }
    @MainActor
    func testStorageRecoveryErrorDisablesSavingButAllowsEditing() {
        let app = launchScenario("xm6", extra: ["--ui-test-storage-error"])
        let editor = openEditor(app)
        XCTAssertTrue(editor.staticTexts["equalizer.storageError"].exists)
        XCTAssertFalse(editor.buttons["Save"].isEnabled)
        XCTAssertTrue(editor.sliders.firstMatch.isEnabled)
    }

    #if MENU_BAR_APP || HYBRID_APP
    @MainActor
    func testMenuBarContentAppearsInDebugHost() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomEqualizerEditorAndPresetSaving() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["equalizer.preset"].firstMatch.click()
        app.menuItems["Custom Equalizer…"].click()

        let editor = app.descendants(matching: .any)["equalizer.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.sliders.count, 6)
        XCTAssertTrue(editor.buttons["Reset Flat"].exists)

        let name = editor.textFields["Preset name"]
        name.click()
        name.typeText("Cinema")
        editor.buttons["Save"].click()
        XCTAssertTrue(editor.buttons["Cinema"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsOpenInsideMenuSurface() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.inline"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Back to headphone controls"].exists)
    }

    @MainActor
    func testSettingsKeyboardNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings.inline"].firstMatch.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["headphones.dashboard"].firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testModeDetailAreaStaysPopulatedWhenLeavingAmbientMode() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "--ui-test-host"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["Ambient sound level"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.checkBoxes["Focus on voice"].exists)
        app.checkBoxes["Focus on voice"].click()
        XCTAssertEqual((app.checkBoxes["Focus on voice"].value as? NSNumber)?.intValue, 1)
        app.buttons["ANC"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Noise cancellation on"].waitForExistence(timeout: 2))
        app.buttons["Off"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Noise control off"].waitForExistence(timeout: 2))
    }
    #endif
}
