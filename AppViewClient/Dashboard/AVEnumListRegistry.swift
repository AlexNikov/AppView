import Foundation
import AppViewShared

final class AVEnumListRegistryKeyValueItem: NSObject {
    var desc: String = ""
    var value: Int = 0
    var availableOSVersion: Int = 0

    static func item(
        withDesc desc: String,
        value: Int,
        availableOSVersion osVersion: Int
    ) -> AVEnumListRegistryKeyValueItem {
        let item = AVEnumListRegistryKeyValueItem()
        item.desc = desc
        item.value = value
        item.availableOSVersion = osVersion
        return item
    }
}

final class AVEnumListRegistry: NSObject {
    static let sharedInstance = AVEnumListRegistry()

    private var data: [String: [AVEnumListRegistryKeyValueItem]] = [:]

    private override init() {
        super.init()
        data = Self.buildData()
    }

    func items(forEnumName enumName: String) -> [AVEnumListRegistryKeyValueItem]? {
        data[enumName]
    }

    func desc(forEnumName enumName: String, value: Int) -> String? {
        guard let items = items(forEnumName: enumName) else {
            assertionFailure()
            return nil
        }
        return items.first(where: { $0.value == value })?.desc
    }

    private static func item(_ desc: String, _ value: Int) -> AVEnumListRegistryKeyValueItem {
        AVEnumListRegistryKeyValueItem.item(withDesc: desc, value: value, availableOSVersion: 0)
    }

    private static func item(_ desc: String, _ value: Int, _ osVersion: Int) -> AVEnumListRegistryKeyValueItem {
        AVEnumListRegistryKeyValueItem.item(withDesc: desc, value: value, availableOSVersion: osVersion)
    }

    private static func buildData() -> [String: [AVEnumListRegistryKeyValueItem]] {
        [
            "UIControlContentVerticalAlignment": [
                item("UIControlContentVerticalAlignmentCenter", 0),
                item("UIControlContentVerticalAlignmentTop", 1),
                item("UIControlContentVerticalAlignmentBottom", 2),
                item("UIControlContentVerticalAlignmentFill", 3),
            ],
            "UIControlContentHorizontalAlignment": [
                item("UIControlContentHorizontalAlignmentCenter", 0),
                item("UIControlContentHorizontalAlignmentLeft", 1),
                item("UIControlContentHorizontalAlignmentRight", 2),
                item("UIControlContentHorizontalAlignmentFill", 3),
                item("UIControlContentHorizontalAlignmentLeading", 4, 11),
                item("UIControlContentHorizontalAlignmentTrailing", 5, 11),
            ],
            "UIViewContentMode": [
                item("UIViewContentModeScaleToFill", 0),
                item("UIViewContentModeScaleAspectFit", 1),
                item("UIViewContentModeScaleAspectFill", 2),
                item("UIViewContentModeRedraw", 3),
                item("UIViewContentModeCenter", 4),
                item("UIViewContentModeTop", 5),
                item("UIViewContentModeBottom", 6),
                item("UIViewContentModeLeft", 7),
                item("UIViewContentModeRight", 8),
                item("UIViewContentModeTopLeft", 9),
                item("UIViewContentModeTopRight", 10),
                item("UIViewContentModeBottomLeft", 11),
                item("UIViewContentModeBottomRight", 12),
            ],
            "UIViewTintAdjustmentMode": [
                item("UIViewTintAdjustmentModeAutomatic", 0),
                item("UIViewTintAdjustmentModeNormal", 1),
                item("UIViewTintAdjustmentModeDimmed", 2),
            ],
            "NSTextAlignment": [
                item("NSTextAlignmentLeft", 0),
                item("NSTextAlignmentCenter", 1),
                item("NSTextAlignmentRight", 2),
                item("NSTextAlignmentJustified", 3),
                item("NSTextAlignmentNatural", 4),
            ],
            "NSLineBreakMode": [
                item("NSLineBreakByWordWrapping", 0),
                item("NSLineBreakByCharWrapping", 1),
                item("NSLineBreakByClipping", 2),
                item("NSLineBreakByTruncatingHead", 3),
                item("NSLineBreakByTruncatingTail", 4),
                item("NSLineBreakByTruncatingMiddle", 5),
            ],
            "UIScrollViewContentInsetAdjustmentBehavior": [
                item("UIScrollViewContentInsetAdjustmentAutomatic", 0),
                item("UIScrollViewContentInsetAdjustmentScrollableAxes", 1),
                item("UIScrollViewContentInsetAdjustmentNever", 2),
                item("UIScrollViewContentInsetAdjustmentAlways", 3),
            ],
            "UITableViewStyle": [
                item("UITableViewStylePlain", 0),
                item("UITableViewStyleGrouped", 1),
            ],
            "UITextFieldViewMode": [
                item("UITextFieldViewModeNever", 0),
                item("UITextFieldViewModeWhileEditing", 1),
                item("UITextFieldViewModeUnlessEditing", 2),
                item("UITextFieldViewModeAlways", 3),
            ],
            "UIAccessibilityNavigationStyle": [
                item("UIAccessibilityNavigationStyleAutomatic", 0),
                item("UIAccessibilityNavigationStyleSeparate", 1),
                item("UIAccessibilityNavigationStyleCombined", 2),
            ],
            "QMUIButtonImagePosition": [
                item("QMUIButtonImagePositionTop", 0),
                item("QMUIButtonImagePositionLeft", 1),
                item("QMUIButtonImagePositionBottom", 2),
                item("QMUIButtonImagePositionRight", 3),
            ],
            "UITableViewCellSeparatorStyle": [
                item("UITableViewCellSeparatorStyleNone", 0),
                item("UITableViewCellSeparatorStyleSingleLine", 1),
                item("UITableViewCellSeparatorStyleSingleLineEtched", 2),
            ],
            "UIBlurEffectStyle": [
                item("UIBlurEffectStyleExtraLight", 0),
                item("UIBlurEffectStyleLight", 1),
                item("UIBlurEffectStyleDark", 2),
                item("UIBlurEffectStyleRegular", 4, 10),
                item("UIBlurEffectStyleProminent", 5, 10),
                item("UIBlurEffectStyleSystemUltraThinMaterial", 6, 13),
                item("UIBlurEffectStyleSystemThinMaterial", 7, 13),
                item("UIBlurEffectStyleSystemMaterial", 8, 13),
                item("UIBlurEffectStyleSystemThickMaterial", 9, 13),
                item("UIBlurEffectStyleSystemChromeMaterial", 10, 13),
                item("UIBlurEffectStyleSystemUltraThinMaterialLight", 11, 13),
                item("UIBlurEffectStyleSystemThinMaterialLight", 12, 13),
                item("UIBlurEffectStyleSystemMaterialLight", 13, 13),
                item("UIBlurEffectStyleSystemThickMaterialLight", 14, 13),
                item("UIBlurEffectStyleSystemChromeMaterialLight", 15, 13),
                item("UIBlurEffectStyleSystemUltraThinMaterialDark", 16, 13),
                item("UIBlurEffectStyleSystemThinMaterialDark", 17, 13),
                item("UIBlurEffectStyleSystemMaterialDark", 18, 13),
                item("UIBlurEffectStyleSystemThickMaterialDark", 19, 13),
                item("UIBlurEffectStyleSystemChromeMaterialDark", 20, 13),
            ],
            "UILayoutConstraintAxis": [
                item("UILayoutConstraintAxisHorizontal", 0),
                item("UILayoutConstraintAxisVertical", 1),
            ],
            "UIStackViewDistribution": [
                item("UIStackViewDistributionFill", 0),
                item("UIStackViewDistributionFillEqually", 1),
                item("UIStackViewDistributionFillProportionally", 2),
                item("UIStackViewDistributionEqualSpacing", 3),
                item("UIStackViewDistributionEqualCentering", 4),
            ],
            "UIStackViewAlignment": [
                item("UIStackViewAlignmentFill", 0),
                item("UIStackViewAlignmentLeading (Top)", 1),
                item("UIStackViewAlignmentFirstBaseline", 2),
                item("UIStackViewAlignmentCenter", 3),
                item("UIStackViewAlignmentTrailing (Bottom)", 4),
                item("UIStackViewAlignmentLastBaseline", 5),
            ],
        ]
    }
}
