import XCTest
@testable import PrismeCore

final class FileDragSessionTests: XCTestCase {
    func testModifierClicksCannotReusePreviousFiles() {
        var session = FileDragSession()
        // A modifier before or after a press is still only a click. Even a
        // pasteboard change cannot authorize reading files without movement.
        session.mouseDown(pasteboardChangeCount: 40)
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 40))
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
        session.mouseUp()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
    }

    func testSelectionOrWindowDragCannotReusePreviousFiles() {
        var session = FileDragSession()
        session.mouseDown(pasteboardChangeCount: 40)
        session.mouseDragged()
        session.mouseDragged()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 40))
    }

    func testFreshPasteboardAndMovementAllowFileRead() {
        var session = FileDragSession()
        session.mouseDown(pasteboardChangeCount: 40)
        session.mouseDragged()
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 41))
        // Tapping or releasing modifiers later does not require more movement.
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 41))
    }

    func testPasteboardMayBePublishedAfterFirstDragEvent() {
        var session = FileDragSession()
        session.mouseDown(pasteboardChangeCount: 40)
        session.mouseDragged()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 40))
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 41))
    }

    func testReleaseEndsEligibilityEvenWithFilesRetained() {
        var session = FileDragSession()
        session.mouseDown(pasteboardChangeCount: 40)
        session.mouseDragged()
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 41))
        session.mouseUp()
        session.mouseDragged()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 42))
    }

    func testRapidMultiSelectionStartsANewGestureForEveryClick() {
        var session = FileDragSession()
        session.mouseDown(pasteboardChangeCount: 40)
        session.mouseDragged()
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 41))
        session.mouseUp()
        // Event tracking must reset even for clicks shorter than a polling tick.
        for _ in 0..<5 {
            session.mouseDown(pasteboardChangeCount: 41)
            XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
            session.mouseUp()
        }
        session.mouseDown(pasteboardChangeCount: 41)
        session.mouseDragged()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
        // A new native drag is valid, even if it contains the very same files.
        XCTAssertTrue(session.allowsPasteboardRead(changeCount: 42))
    }

    func testStartupDuringAnExistingDragIsIgnored() {
        var session = FileDragSession()
        session.mouseDragged()
        XCTAssertFalse(session.allowsPasteboardRead(changeCount: 41))
    }
}
