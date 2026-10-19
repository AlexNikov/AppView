import AppViewShared

// MARK: - Table rows & oid map

extension AVHierarchyDataSource {
    func numberOfRows() -> Int {
        displayingFlatItems?.count ?? 0
    }

    func itemAtRow(_ index: Int) -> AppViewDisplayItem? {
        if index < 0 { return nil }
        guard let displayingFlatItems, displayingFlatItems.appview_hasIndex(index) else { return nil }
        return displayingFlatItems[index]
    }

    func row(forItem item: AppViewDisplayItem) -> Int {
        displayingFlatItems?.firstIndex(of: item) ?? NSNotFound
    }

    func displayItem(withOid oid: UInt) -> AppViewDisplayItem? {
        oidToDisplayItemMap[oid]
    }

    func rebuildOidToDisplayItemMap() {
        guard let rawFlatItems else {
            oidToDisplayItemMap = [:]
            return
        }
        var map: [UInt: AppViewDisplayItem] = [:]
        map.reserveCapacity(rawFlatItems.count * 2)
        for obj in rawFlatItems {
            if let viewObject = obj.viewObject, viewObject.oid != 0 {
                map[viewObject.oid] = obj
            }
            if let layerObject = obj.layerObject, layerObject.oid != 0 {
                map[layerObject.oid] = obj
            }
        }
        oidToDisplayItemMap = map
    }
}
