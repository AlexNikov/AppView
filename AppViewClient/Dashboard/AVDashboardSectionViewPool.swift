import Foundation
import AppViewShared

final class AVDashboardSectionViewPool: NSObject {
    private var dequeuedViews = Set<AVDashboardSectionView>()
    private var cache: [String: [AVDashboardSectionView]] = [:]

    func recycleAll() {
        dequeuedViews.removeAll()
    }

    func dequeView(for section: AppViewAttributesSection) -> AVDashboardSectionView {
        let key = cacheKey(for: section)
        if cache[key] == nil {
            cache[key] = []
        }
        for view in cache[key] ?? [] {
            if dequeuedViews.contains(view) { continue }
            dequeuedViews.insert(view)
            return view
        }
        let newView = AVDashboardSectionView()
        dequeuedViews.insert(newView)
        cache[key, default: []].append(newView)
        return newView
    }

    private func cacheKey(for section: AppViewAttributesSection) -> String {
        if !section.isUserCustom() {
            return section.identifier ?? ""
        }
        let titles = (section.attributes ?? []).map { $0.displayTitle ?? "" }
        return titles.joined(separator: ",")
    }
}
