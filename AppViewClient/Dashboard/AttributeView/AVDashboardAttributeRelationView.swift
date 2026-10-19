import AppKit
import AppViewShared

final class AVDashboardAttributeRelationView: AVDashboardAttributeStringArrayView {
    override func stringList(with attribute: AppViewAttribute) -> [String] {
        if let cache = attribute.appview_getBindObject(forKey: "cachedDemangled") as? [String] {
            return cache
        }
        guard case .customObject(let rawValue)? = attribute.value,
              let result = rawValue as? [String] else { return [] }
        let demangled = result.map { Self.formatRelation($0) }
        attribute.appview_bindObject(demangled, forKey: "cachedDemangled")
        return demangled
    }

    /// Formats `(Module.Type *) -> ivar` / `(A : B *)` for display:
    /// - drop the ObjC `*`
    /// - split `Module.Type` across lines (same as Class attribute)
    private static func formatRelation(_ rawText: String) -> String {
        // (AAA : BBB *) — rare ObjC protocol-style host
        if let regex = try? NSRegularExpression(pattern: #"\(\s*([\w.]+)\s*:\s*([\w.]+)\s*\*?\s*\)"#),
           let match = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
           match.numberOfRanges == 3 {
            let ns = rawText as NSString
            let d1 = AVSwiftDemangler.displayQualifiedName(input: ns.substring(with: match.range(at: 1)))
            let d2 = AVSwiftDemangler.displayQualifiedName(input: ns.substring(with: match.range(at: 2)))
            let replacement = "(\(d1) : \(d2))"
            return ns.replacingCharacters(in: match.range(at: 0), with: replacement)
        }

        // (AAA *) or (Module.Type *) — may be followed by `.view` / ` -> ivar`
        if let regex = try? NSRegularExpression(pattern: #"\(\s*([\w.]+)\s*\*?\s*\)"#),
           let match = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
           match.numberOfRanges == 2 {
            let ns = rawText as NSString
            let display = AVSwiftDemangler.displayQualifiedName(input: ns.substring(with: match.range(at: 1)))
            return ns.replacingCharacters(in: match.range(at: 0), with: "(\(display))")
        }

        return rawText
    }
}
