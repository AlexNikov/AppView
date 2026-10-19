//
//  InspectorHiddenPreviewTests.swift
//  AppViewClientUITests
//

import XCTest

final class InspectorHiddenPreviewTests: AppViewUITestCase {
    private let hiddenBadgeTitle = "HiddenBadgeView"

    func testPreviewStructureHidesHiddenLayerByDefault() throws {
        launchAppViewForUITest()
        let lines = waitForPreviewStructure()
        recordPreviewFixtureIfRequested(lines, name: "preview-structure-hidden-off.norm")

        AppViewPreviewStructureCompare.assertHiddenPreviewTitles([], in: lines)
        AppViewPreviewStructureCompare.assertTreeMatchesFixture(
            actual: lines,
            fixtureName: "preview-structure-hidden-off.norm"
        )
    }

    func testShowHiddenRevealsLayerInPreviewStructure() throws {
        launchAppViewForUITest(showHiddenItems: true)
        let lines = waitForPreviewStructure()
        recordPreviewFixtureIfRequested(lines, name: "preview-structure-hidden-on.norm")

        AppViewPreviewStructureCompare.assertHiddenPreviewTitles([hiddenBadgeTitle], in: lines)
        AppViewPreviewStructureCompare.assertTreeMatchesFixture(
            actual: lines,
            fixtureName: "preview-structure-hidden-on.norm"
        )
    }

    private func recordPreviewFixtureIfRequested(_ lines: [String], name: String) {
        guard AppViewUITestConfig.load().recordPreviewFixtures else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        let body = lines.joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}
