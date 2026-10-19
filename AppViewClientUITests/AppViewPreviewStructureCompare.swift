//
//  AppViewPreviewStructureCompare.swift
//  AppViewClientUITests
//

import Foundation
import XCTest

enum AppViewPreviewStructureCompare {
    private static let treeLinePrefix = "oid="

    static func treeLines(from lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix(treeLinePrefix) }
    }

    static func stableKey(for line: String) -> String {
        if let range = line.range(of: " root=(") {
            return String(line[..<range.lowerBound])
        }
        if let range = line.range(of: " pos=(") {
            return String(line[..<range.lowerBound])
        }
        return line
    }

    static func loadFixture(named name: String, file: StaticString = #file, line: UInt = #line) -> [String] {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? "norm" : (name as NSString).pathExtension
        let url = Bundle(for: AppViewUITestCase.self).url(forResource: base, withExtension: ext)
            ?? filesystemFixtureURL(for: name)
        guard let url else {
            XCTFail("Missing preview fixture \(name)", file: file, line: line)
            return []
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Failed to read preview fixture \(name)", file: file, line: line)
            return []
        }
        return text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func filesystemFixtureURL(for name: String) -> URL? {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Fixtures/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    static func hiddenPreviewTitles(from lines: [String]) -> [String] {
        guard let line = lines.first(where: { $0.hasPrefix("hiddenPreviewTitles=") }) else { return [] }
        let raw = line.dropFirst("hiddenPreviewTitles=".count)
        if raw.isEmpty { return [] }
        return raw.split(separator: ",").map(String.init)
    }

    static func assertHiddenPreviewTitles(
        _ expected: [String],
        in lines: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(hiddenPreviewTitles(from: lines), expected.sorted(), file: file, line: line)
    }

    static func assertTreeMatchesFixture(
        actual lines: [String],
        fixtureName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if AppViewUITestConfig.load().recordPreviewFixtures {
            return
        }
        let expected = loadFixture(named: fixtureName, file: file, line: line)
        guard !expected.isEmpty else { return }

        let actualTree = Set(treeLines(from: lines).map(stableKey(for:)))
        let expectedTree = Set(
            treeLines(from: expected)
                .filter { !$0.hasPrefix("hiddenPreviewTitles=") }
                .map(stableKey(for:))
        )

        let missing = expectedTree.subtracting(actualTree).sorted()
        let extra = actualTree.subtracting(expectedTree).sorted()

        if missing.isEmpty && extra.isEmpty {
            return
        }

        var message = "Preview structure tree mismatch for \(fixtureName)"
        if !missing.isEmpty {
            message += "\nMissing (\(missing.count)):\n" + missing.prefix(10).joined(separator: "\n")
        }
        if !extra.isEmpty {
            message += "\nExtra (\(extra.count)):\n" + extra.prefix(10).joined(separator: "\n")
        }
        XCTFail(message, file: file, line: line)
    }

    static func assertContainsTitle(_ title: String, in lines: [String], file: StaticString = #file, line: UInt = #line) {
        let needle = "title=\"\(title)\""
        XCTAssertTrue(
            treeLines(from: lines).contains { $0.contains(needle) },
            "Expected preview structure to contain \(needle)",
            file: file,
            line: line
        )
    }

    static func assertExcludesTitle(_ title: String, in lines: [String], file: StaticString = #file, line: UInt = #line) {
        let needle = "title=\"\(title)\""
        XCTAssertFalse(
            treeLines(from: lines).contains { $0.contains(needle) },
            "Expected preview structure to exclude \(needle)",
            file: file,
            line: line
        )
    }
}
