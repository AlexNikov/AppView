import AppKit
import AppViewShared

final class AVDashboardAttributeClassView: AVDashboardAttributeStringArrayView {
    override func stringList(with attribute: AppViewAttribute) -> [String] {
        guard case .customObject(let rawValue)? = attribute.value,
              let lists = rawValue as? [[String]] else { return [] }
        return lists.map { rawClassList in
            rawClassList
                .map { AVSwiftDemangler.displayQualifiedName(input: $0) }
                .joined(separator: "\n")
        }
    }
}
