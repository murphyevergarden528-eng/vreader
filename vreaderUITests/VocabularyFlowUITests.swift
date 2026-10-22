import XCTest

/// CI uses a controlled TXT fixture because the local real-book folder is gitignored.
@MainActor
final class VocabularyFlowUITests: XCTestCase {
    func testVocabularyIsReachableFromEmptyLibrary() {
        let app = launchApp(seed: .empty, resetPreferences: true)
        let entry = app.buttons["vocabularyToolbarButton"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.staticTexts["vocabularyEmptyState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["vocabularyImportButton"].exists)
    }

    func testCollectionThroughRealTXTSelectionThenOfflineReview() {
        let app = launchApp(seed: .positionTest, resetPreferences: true)
        tapBook(titled: "Position Test Book", in: app)
        let text = app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "value CONTAINS 'restoredOffset:' AND NOT value CONTAINS 'restoredOffset:none'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: text)], timeout: 15), .completed)
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 1.5)
        let collect = app.buttons["selectionPopoverVocabulary"]
        XCTAssertTrue(collect.waitForExistence(timeout: 5))
        collect.tap()
        let term = app.textFields["vocabularyTermField"]
        XCTAssertTrue(term.waitForExistence(timeout: 5))
        XCTAssertFalse((term.value as? String ?? "").isEmpty)
        let definition = app.textViews["vocabularyDefinitionField"]
        XCTAssertTrue(definition.exists)
        definition.tap()
        definition.typeText("来自真实选区的测试释义")
        app.buttons["vocabularySaveButton"].tap()
        XCTAssertTrue(term.waitForDisappearance(timeout: 5))
        let back = app.buttons[AccessibilityID.readerBackButton]
        if !back.exists || !back.isHittable { text.tap() }
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        app.buttons["vocabularyToolbarButton"].tap()
        XCTAssertTrue(app.staticTexts["来自真实选区的测试释义"].waitForExistence(timeout: 5))
        app.buttons["vocabularyStartReviewButton"].tap()
        let answer = app.buttons["vocabularyShowAnswerButton"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vocabularyRatingGood"].exists)
        answer.tap()
        app.buttons["vocabularyRatingGood"].tap()
        XCTAssertTrue(app.staticTexts["vocabularyReviewComplete"].waitForExistence(timeout: 5))
    }
}
