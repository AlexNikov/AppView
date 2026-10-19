import Foundation

final class AVJSONAttributeItem: NSObject {
    var titleText: String?
    var desc: String?
    var expanded = true
    var subItems: [AVJSONAttributeItem] = []
    var indentation = 0

    override init() {
        super.init()
        expanded = true
        subItems = []
    }

    func flatItems() -> [AVJSONAttributeItem] {
        var array: [AVJSONAttributeItem] = [self]
        if expanded {
            for obj in subItems {
                obj.indentation = indentation + 1
                array.append(contentsOf: obj.flatItems())
            }
        }
        return array
    }
}
