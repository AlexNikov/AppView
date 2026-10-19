//
//  DanceScriptManager.swift
//  AppViewClient
//

import AppCenter
import AppCenterAnalytics
import Foundation

class DanceScriptManager: NSObject {
    static let shared: DanceScriptManager = {
        DanceScriptManager()
    }()

    func handleText(_ json: String?) {
        guard let json else {
            AlertError(AVAppViewClientErrors.inner, CurrentKeyWindow)
            return
        }
        guard let jsonData = json.data(using: .utf8) else { return }

        do {
            let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let dict else {
                let msg = "Unexpected format: \(json)"
                AlertErrorText("Failed", msg, CurrentKeyWindow)
                return
            }
            guard let type = dict["type"] as? String,
                  let method = dict["method"] as? String,
                  let path = dict["build_path"] as? String else {
                let msg = "Unexpected format: \(json)"
                AlertErrorText("Failed", msg, CurrentKeyWindow)
                return
            }
            execute(withType: type, method: method, path: path)
        } catch {
            let msg = "Failed to parse: \(json)"
            AlertErrorText("Failed", msg, CurrentKeyWindow)
            assertionFailure()
        }
    }

    private func copyScriptFromAppToDisk() -> String? {
        let newScriptPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("AppView_DanceJump.sh")
        if FileManager.default.fileExists(atPath: newScriptPath) {
            return newScriptPath
        }

        guard let scriptURL = Bundle.main.url(forResource: "DanceScript", withExtension: "sh") else {
            AlertErrorText("Failed", "Cannot find script", CurrentKeyWindow)
            return nil
        }
        let scriptPath = scriptURL.relativePath
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            let text = "Cannot find script: \(scriptPath)"
            AlertErrorText("Failed", text, CurrentKeyWindow)
            return nil
        }

        do {
            try FileManager.default.copyItem(atPath: scriptPath, toPath: newScriptPath)
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: newScriptPath)
        } catch {
            AlertErrorText("Failed", "Copy script error", CurrentKeyWindow)
            return nil
        }

        guard FileManager.default.fileExists(atPath: newScriptPath) else {
            AlertErrorText("Failed", "Copy script weird error", CurrentKeyWindow)
            return nil
        }
        return newScriptPath
    }

    private func execute(withType type: String, method: String, path buildPath: String) {
        guard let scriptPath = copyScriptFromAppToDisk() else { return }

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "\(scriptPath) \(buildPath) \(type) \(method)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            NSLog("脚本执行输出：%@", output)
        }

        Analytics.trackEvent("DanceJump")
    }
}
