//
//  InspectorSmokeTests.swift
//  AppViewClientUITests
//

import XCTest

final class InspectorSmokeTests: AppViewUITestCase {
    func testInspectorOpens() throws {
        launchAppViewForUITest()
        _ = waitForInspectorReady()
        XCTAssertTrue(hierarchyOutline.waitForExistence(timeout: 30))
    }

    func testHierarchyOutlineHasRows() throws {
        launchAppViewForUITest()
        _ = waitForInspectorReady()
        waitForHierarchyRows(minimum: 5)
    }
}
