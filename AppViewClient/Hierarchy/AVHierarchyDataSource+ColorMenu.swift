import AppKit
import AppViewShared

// MARK: - Private helper types

private class AVSelectColorItem: NSObject {
    var title: String = ""
    var color: NSColor?

    static func item(title: String, color: NSColor?) -> AVSelectColorItem {
        let item = AVSelectColorItem()
        item.title = title
        item.color = color
        return item
    }
}

private class AVSelectColorItemsSection: NSObject {
    var title: String = ""
    var items: [AVSelectColorItem] = [] {
        didSet {
            items.sort { $0.title.caseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

// MARK: - Color menu

extension AVHierarchyDataSource {
    func alias(forColor color: NSColor?) -> [String]? {
        guard let color else { return nil }
        return colorToAliasMap[color.rgbaString]
    }

    func setUpColors() {
        var colorToAliasMap: [String: [String]] = [:]
        var aliasColorItemsOrSections: [Any] = []

        rawHierarchyInfo?.colorAlias?.forEach { key, colorOrDict in
            if let color = colorOrDict as? NSColor {
                if let colorDesc = color.rgbaString as String? {
                    if colorToAliasMap[colorDesc] == nil {
                        colorToAliasMap[colorDesc] = []
                    }
                    colorToAliasMap[colorDesc]?.append(key)
                }
                aliasColorItemsOrSections.append(AVSelectColorItem.item(title: key, color: color))

            } else if let dict = colorOrDict as? [String: NSColor] {
                let section = AVSelectColorItemsSection()
                section.title = key
                var aliasItems: [AVSelectColorItem] = []

                dict.forEach { colorAliaName, colorObj in
                    if let colorDesc = colorObj.rgbaString as String? {
                        if colorToAliasMap[colorDesc] == nil {
                            colorToAliasMap[colorDesc] = []
                        }
                        colorToAliasMap[colorDesc]?.append(colorAliaName)
                    }
                    aliasItems.append(AVSelectColorItem.item(title: colorAliaName, color: colorObj))
                }

                if !aliasItems.isEmpty {
                    section.items = aliasItems
                    aliasColorItemsOrSections.append(section)
                }
            } else {
                assertionFailure()
            }
        }

        aliasColorItemsOrSections.sort { obj1, obj2 in
            switch (obj1, obj2) {
            case let (item1 as AVSelectColorItem, item2 as AVSelectColorItem):
                return item1.title.caseInsensitiveCompare(item2.title) == .orderedAscending
            case (_ as AVSelectColorItem, _ as AVSelectColorItemsSection):
                return true
            case (_ as AVSelectColorItemsSection, _ as AVSelectColorItem):
                return false
            case let (sec1 as AVSelectColorItemsSection, sec2 as AVSelectColorItemsSection):
                return sec1.title.caseInsensitiveCompare(sec2.title) == .orderedAscending
            default:
                assertionFailure()
                return true
            }
        }

        self.colorToAliasMap = colorToAliasMap
        selectColorMenu = makeMenu(
            withAliasColorItemsOrSections: aliasColorItemsOrSections,
            usingRGBAFormat: AVPreferenceMain().rgbaFormat
        )
    }

    private func makeMenu(
        withAliasColorItemsOrSections aliasColorItemsOrSections: [Any],
        usingRGBAFormat rgbaFormat: Bool
    ) -> NSMenu {
        var menuModel: [Any] = []
        menuModel.append(AVSelectColorItem.item(title: "nil", color: nil))
        menuModel.append(AVSelectColorItem.item(title: "clear color", color: AppViewColorRGBAMake(0, 0, 0, 0)))

        let defaultColors: [NSColor] = [
            AppViewColorMake(0, 0, 0),
            AppViewColorMake(126, 126, 126),
            AppViewColorMake(255, 255, 255),
            AppViewColorRGBAMake(0, 166, 248, 0.5),
            AppViewColorMake(253, 62, 0),
            AppViewColorMake(105, 190, 0),
            AppViewColorMake(254, 182, 2),
        ]
        let defaultColorItems = defaultColors.enumerated().map { _, value -> AVSelectColorItem in
            let item = AVSelectColorItem()
            item.color = value
            item.title = rgbaFormat ? value.rgbaString : value.hexString
            return item
        }
        menuModel.append(contentsOf: defaultColorItems)

        let defaultItemsCount = menuModel.count
        menuModel.append(contentsOf: aliasColorItemsOrSections)

        let menu = NSMenu()
        for (idx, itemOrSection) in menuModel.enumerated() {
            if idx == defaultItemsCount {
                menu.addItem(.separator())
            }

            if let itemsSection = itemOrSection as? AVSelectColorItemsSection {
                let sectionMenuItem = NSMenuItem()
                sectionMenuItem.image = NSImage(size: NSSize(width: 1, height: 22))
                sectionMenuItem.title = itemsSection.title
                menu.addItem(sectionMenuItem)

                let submenu = NSMenu()
                for subAliasItem in itemsSection.items {
                    submenu.addItem(menuItem(fromColorItem: subAliasItem))
                }
                sectionMenuItem.submenu = submenu

            } else if let colorItem = itemOrSection as? AVSelectColorItem {
                menu.addItem(menuItem(fromColorItem: colorItem))
            } else {
                assertionFailure()
            }
        }

        menu.addItem(.separator())
        let otherItem = NSMenuItem()
        otherItem.image = NSImage(size: NSSize(width: 1, height: 22))
        otherItem.title = NSLocalizedString("Other…", comment: "")
        otherItem.tag = customColorMenuItemTag
        menu.addItem(otherItem)

        menu.addItem(.separator())
        let toggleItem = NSMenuItem()
        toggleItem.image = NSImage(size: NSSize(width: 1, height: 22))
        toggleItem.title = rgbaFormat
            ? NSLocalizedString("Switch color format to HEX", comment: "")
            : NSLocalizedString("Switch color format to RGBA", comment: "")
        toggleItem.tag = toggleColorFormatMenuItemTag
        menu.addItem(toggleItem)

        return menu
    }

    private func menuItem(fromColorItem item: AVSelectColorItem) -> NSMenuItem {
        let image = AVColorIndicatorLayer.image(
            with: item.color,
            shapeSize: NSSize(width: 20, height: 20),
            insets: NSEdgeInsets(top: 4, left: 5, bottom: 4, right: 6)
        )
        let menuItem = NSMenuItem()
        menuItem.image = image
        menuItem.title = item.title
        menuItem.representedObject = item.color
        return menuItem
    }
}
