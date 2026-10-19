//
//  AppViewUITestConfig.swift
//  AppViewClientUITests
//

import Foundation

struct AppViewUITestConfig {
    let recordPreviewFixtures: Bool

    static func load() -> AppViewUITestConfig {
        if let config = loadFromRepoConfigFile() {
            return config
        }
        return AppViewUITestConfig(
            recordPreviewFixtures: ProcessInfo.processInfo.environment["APPVIEW_RECORD_PREVIEW_FIXTURE"] == "1"
        )
    }

    private static func loadFromRepoConfigFile() -> AppViewUITestConfig? {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = url
                .appendingPathComponent("../../appview-verify-logs/ui-test-config.json")
                .standardizedFileURL
            if let data = try? Data(contentsOf: candidate),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return AppViewUITestConfig(
                    recordPreviewFixtures: (json["recordPreviewFixtures"] as? Bool) ?? false
                )
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
