//
//  AVHelper.swift
//  AppView
//

import AppKit
import AppViewShared

class AVHelper: NSObject {
    static let sharedInstance: AVHelper = {
        AVHelper()
    }()

    var tempImageFiles: NSMutableArray?

    static func italicFont(ofSize fontSize: CGFloat) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    static func appviewReadableVersion() -> String {
        let infoDictionary = Bundle.main.infoDictionary
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func presentError(_ error: NSError, window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static func openAppViewOfficialWebsite() {
        NSWorkspace.shared.open(URL(string: "https://appview.work")!)
    }

    static func openCustomConfigWebsite() {
        NSWorkspace.shared.open(URL(string: "https://appview.work/faq/config-file/")!)
    }

    private static var _isEnglish: Bool?

    static func isEnglish() -> Bool {
        if let cached = _isEnglish { return cached }
        let languages = Locale.preferredLanguages
        let language = languages.first ?? "en"
        let result = !language.hasPrefix("zh")
        _isEnglish = result
        return result
    }

    static func accentColor() -> NSColor {
        NSColor.controlAccentColor
    }

    static func bestMatchesInCandidates(_ candidates: [String], input: String, maxResultsCount: UInt) -> [String] {
        var topResults: [[String: Any]] = []
        var lowestScore: CGFloat = 1
        let inputLower = input.lowercased()

        for candidate in candidates {
            if lowestScore >= 1 && topResults.count >= maxResultsCount {
                break
            }
            let candidateLower = candidate.lowercased()
            let score: CGFloat
            if candidateLower.contains(inputLower) {
                score = 1
            } else {
                score = inputLower.score(against: candidateLower, fuzziness: NSNumber(value: 0.5))
            }

            if topResults.count < maxResultsCount {
                topResults.append(["string": candidate, "score": score])
                if score < lowestScore { lowestScore = score }
                continue
            }

            if score > lowestScore {
                let scores = topResults.map { ($0["score"] as? NSNumber)?.doubleValue ?? 0 }
                if let idxToDelete = indexOfSmallestNumber(in: scores) {
                    topResults.remove(at: idxToDelete)
                    topResults.append(["string": candidate, "score": score])
                    let newScores = topResults.map { ($0["score"] as? NSNumber)?.doubleValue ?? 0 }
                    lowestScore = smallestNumber(in: newScores)
                }
            }
        }

        topResults.sort { a, b in
            let score1 = (a["score"] as? NSNumber)?.doubleValue ?? 0
            let score2 = (b["score"] as? NSNumber)?.doubleValue ?? 0
            if score1 > score2 { return true }
            if score1 < score2 { return false }
            return false
        }

        return topResults.compactMap { $0["string"] as? String }
    }

    private static func indexOfSmallestNumber(in array: [Double]) -> Int? {
        guard !array.isEmpty else {
            assertionFailure("_indexOfSmallestNumberInArray")
            return nil
        }
        var index = NSNotFound
        var smallestNumber = CGFloat.greatestFiniteMagnitude
        for (idx, obj) in array.enumerated() {
            if obj < smallestNumber {
                smallestNumber = CGFloat(obj)
                index = idx
            }
        }
        return index == NSNotFound ? nil : index
    }

    private static func smallestNumber(in array: [Double]) -> CGFloat {
        guard !array.isEmpty else {
            assertionFailure("_smallestNumberInArray")
            return 0
        }
        return CGFloat(array.min() ?? 0)
    }

    static func scrollableTextView() -> NSScrollView {
        NSTextView.scrollableTextView()
    }

    static func validateFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !cgRectIsNaN(frame) && !cgRectIsInf(frame) && !cgRectIsUnreasonable(frame)
    }

    private static func cgRectIsNaN(_ rect: CGRect) -> Bool {
        rect.origin.x.isNaN || rect.origin.y.isNaN || rect.size.width.isNaN || rect.size.height.isNaN
    }

    private static func cgRectIsInf(_ rect: CGRect) -> Bool {
        rect.origin.x.isInfinite || rect.origin.y.isInfinite || rect.size.width.isInfinite || rect.size.height.isInfinite
    }

    private static func cgRectIsUnreasonable(_ rect: CGRect) -> Bool {
        abs(rect.origin.x) > 100000 || abs(rect.origin.y) > 100000 ||
        rect.size.width < 0 || rect.size.height < 0 ||
        rect.size.width > 100000 || rect.size.height > 100000
    }
}
