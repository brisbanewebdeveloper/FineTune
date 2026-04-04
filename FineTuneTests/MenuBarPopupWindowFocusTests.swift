import AppKit
import XCTest
@testable import FineTune

final class MenuBarPopupWindowFocusTests: XCTestCase {

    func testPopupOwnedWindowMatchesPopupAndChildPanels() {
        let popupWindow = makeWindow()
        let childPanel = makePanel()
        popupWindow.addChildWindow(childPanel, ordered: .above)

        XCTAssertTrue(MenuBarPopupWindowFocus.isPopupOwnedWindow(popupWindow, popupWindow: popupWindow))
        XCTAssertTrue(MenuBarPopupWindowFocus.isPopupOwnedWindow(childPanel, popupWindow: popupWindow))
        XCTAssertFalse(MenuBarPopupWindowFocus.isPopupOwnedWindow(makeWindow(), popupWindow: popupWindow))

        popupWindow.removeChildWindow(childPanel)
    }

    func testPopupResignIsIgnoredWhileChildPanelIsAttached() {
        let popupWindow = makeWindow()
        let childPanel = makePanel()
        popupWindow.addChildWindow(childPanel, ordered: .above)

        XCTAssertFalse(MenuBarPopupWindowFocus.shouldHandlePopupResign(resigningWindow: popupWindow, popupWindow: popupWindow))
        XCTAssertFalse(MenuBarPopupWindowFocus.shouldHandlePopupResign(resigningWindow: childPanel, popupWindow: popupWindow))

        popupWindow.removeChildWindow(childPanel)
    }

    func testPopupResignIsHandledAfterChildPanelIsRemoved() {
        let popupWindow = makeWindow()
        let childPanel = makePanel()
        popupWindow.addChildWindow(childPanel, ordered: .above)
        popupWindow.removeChildWindow(childPanel)

        XCTAssertTrue(MenuBarPopupWindowFocus.shouldHandlePopupResign(resigningWindow: popupWindow, popupWindow: popupWindow))
        XCTAssertFalse(MenuBarPopupWindowFocus.shouldHandlePopupResign(resigningWindow: makeWindow(), popupWindow: popupWindow))
        XCTAssertFalse(MenuBarPopupWindowFocus.shouldHandlePopupResign(resigningWindow: popupWindow, popupWindow: nil))
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func makePanel() -> NSPanel {
        NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }
}
