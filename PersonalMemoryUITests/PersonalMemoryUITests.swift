import XCTest

final class PersonalMemoryUITests: XCTestCase {
    @MainActor
    func testInputSaveAndProcessRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let input = app.descendants(matching: .any).matching(identifier: "memory-input").firstMatch
        let save = app.buttons["memory-save"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertFalse(save.isEnabled)
        let note = "Walk in the park " + UUID().uuidString.prefix(6)
        input.tap()
        input.typeText(note)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        capture(app, "01-saved")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 8))
        XCTAssertTrue(input.exists)
        XCTAssertFalse(save.isEnabled)
        capture(app, "02-after-relaunch")
        // Preserve the note and any existing data; do not reset the app container.
    }

    @MainActor
    func testReceivedRecordingPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let tab = app.tabBars.buttons["録音"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        // Real 7.1-second Watch recording received on this acceptance device.
        // No seeding, replacement, deletion, or mock playback in this test.
        let recording = app.buttons["play-recording-05BFF1B3-A812-4399-962C-F9AA0878DC2A"]
        XCTAssertTrue(recording.waitForExistence(timeout: 5), "Requires the preserved real-device audio fixture")
        if !recording.isHittable { app.swipeUp() }
        recording.tap()
        let status = app.staticTexts["playback-status"]
        expectation(for: NSPredicate(format: "label == %@", "再生中"), evaluatedWith: status)
        waitForExpectations(timeout: 8)
        capture(app, "03-recording-playing")
        recording.tap()
        expectation(for: NSPredicate(format: "label == %@", "停止しました"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        recording.tap()
        expectation(for: NSPredicate(format: "label == %@", "再生を終了しました"), evaluatedWith: status)
        waitForExpectations(timeout: 12)
        capture(app, "04-recording-finished")
        XCTAssertTrue(recording.isEnabled)
    }

    @MainActor
    func testRecordingShareSheetCanBeCancelled() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let tab = app.tabBars.buttons["録音"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        // Simulator-only system-tone fixture, not private user speech. No transfer is submitted.
        let share = app.buttons["share-recording-5C0B33C3-3D80-4894-91BF-A7C5674E3C36"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        capture(app, "05-share-entry")
        share.tap()
        // The system share UI is hosted by a separate service, not our wrapper's root view.
        let sheet = app.navigationBars["UIActivityContentView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["LP.CaptionBar.TopCaption"].label, "5C0B33C3-3D80-4894-91BF-A7C5674E3C36")
        capture(app, "06-share-sheet")
        let close = app.buttons["header.closeButton"]
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isEnabled)
        XCTAssertTrue(app.staticTexts["共有画面を閉じました。Mac側で受信を確認してください。原本は保持しています。"].exists)
        capture(app, "07-share-cancelled")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
