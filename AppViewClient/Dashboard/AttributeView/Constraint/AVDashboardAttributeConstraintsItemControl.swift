import AppKit
import AppViewShared

final class AVDashboardAttributeConstraintsItemControl: AVDashboardAttributeRowControl {
    /// Code variable name for a view item, when the tree knows one. Set before `constraint`.
    var variableName: ((AppViewObject) -> String?)?

    var constraint: AppViewAutoLayoutConstraint? {
        didSet {
            guard let constraint else { return }
            label.stringValue = string(from: constraint)
            updateLabelColor()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        didChangeAppearance = { [weak self] _, _ in
            self?.updateLabelColor()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Set by the dashboard after a Layout Issues click; cleared on the next detail refresh.
    var isWarningHighlighted = false {
        didSet {
            guard isWarningHighlighted != oldValue else { return }
            updateLabelColor()
        }
    }

    private func updateLabelColor() {
        guard let constraint else { return }
        if isWarningHighlighted {
            label.textColor = .systemOrange
        } else if constraint.effective {
            label.textColor = .labelColor
        } else if effectiveAppearance.lk_isDarkMode {
            label.textColor = AppViewColorMake(130, 131, 132)
        } else {
            label.textColor = AppViewColorMake(150, 151, 152)
        }
    }

    /// `width = 120`, `top = titleLabel.bottom + 8`: the selected view is not named, other views use their code
    /// variable when known and `(Class*)` otherwise.
    private func anchor(_ object: AppViewObject?, type: AppViewConstraintItemType, attribute: Int) -> String {
        let attributeText = AppViewAutoLayoutConstraint.description(withAttributeInt: attribute)
        if type == .self { return attributeText }
        let itemText: String
        if type == .view, let object, let name = variableName?(object) {
            itemText = name
        } else {
            itemText = AppViewAutoLayoutConstraint.descriptionWithItemObject(object, type: type, detailed: false)
        }
        return "\(itemText).\(attributeText)"
    }

    private func string(from constraint: AppViewAutoLayoutConstraint) -> String {
        var result = anchor(constraint.firstItem, type: constraint.firstItemType, attribute: constraint.firstAttribute)
            + " " + AppViewAutoLayoutConstraint.symbol(with: constraint.relation)

        if constraint.secondAttribute == 0 {
            result += " \(NSString.appview_string(from: constraint.constant, decimal: 3))"
        } else {
            result += " " + anchor(constraint.secondItem, type: constraint.secondItemType, attribute: constraint.secondAttribute)
            if constraint.multiplier != 1 {
                result += " * \(NSString.appview_string(from: constraint.multiplier, decimal: 3))"
            }
            if constraint.constant > 0 {
                result += " + \(NSString.appview_string(from: constraint.constant, decimal: 3))"
            } else if constraint.constant < 0 {
                result += " - \(NSString.appview_string(from: -constraint.constant, decimal: 3))"
            }
        }
        if constraint.priority != 1000 {
            result += " @ \(constraint.priority)"
        }
        return result
    }
}
