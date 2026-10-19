import AppKit
import AppViewShared

extension AttributeValue {
    var dashboardDoubleValue: Double {
        switch self {
        case .char(let v): return Double(v)
        case .int(let v): return Double(v)
        case .short(let v): return Double(v)
        case .long(let v): return Double(v)
        case .longLong(let v): return Double(v)
        case .unsignedChar(let v): return Double(v)
        case .unsignedInt(let v): return Double(v)
        case .unsignedShort(let v): return Double(v)
        case .unsignedLong(let v): return Double(v)
        case .unsignedLongLong(let v): return Double(v)
        case .float(let v): return Double(v)
        case .double(let v): return v
        case .bool(let v): return v ? 1 : 0
        default: return 0
        }
    }

    var dashboardBoolValue: Bool {
        if case .bool(let value) = self { return value }
        return false
    }

    var dashboardIntValue: Int {
        switch self {
        case .int(let value): return Int(value)
        case .long(let value): return value
        case .longLong(let value): return Int(value)
        case .unsignedInt(let value): return Int(value)
        case .unsignedLong(let value): return Int(value)
        case .unsignedLongLong(let value): return Int(value)
        default: return 0
        }
    }

    var dashboardStringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var dashboardScalarDisplayString: String {
        switch self {
        case .char(let value): return String(value)
        case .int(let value): return String(value)
        case .short(let value): return String(value)
        case .long(let value): return String(value)
        case .longLong(let value): return String(value)
        case .unsignedChar(let value): return String(value)
        case .unsignedInt(let value): return String(value)
        case .unsignedShort(let value): return String(value)
        case .unsignedLong(let value): return String(value)
        case .unsignedLongLong(let value): return String(value)
        case .float(let value): return String(value)
        case .double(let value): return String(value)
        case .selector(let value): return NSStringFromSelector(value)
        case .classRef(let value): return value.map { NSStringFromClass($0) } ?? "nil"
        case .string(let value): return value
        default: return String(describing: self)
        }
    }

    static func from(double: Double, attrType: AppViewAttrType) -> AttributeValue {
        switch attrType {
        case .float: return .float(Float(double))
        case .double: return .double(double)
        case .int, .enumInt: return .int(Int32(double))
        case .short: return .short(Int16(double))
        case .long, .enumLong: return .long(Int(double))
        case .longLong: return .longLong(Int64(double))
        case .char: return .char(Int8(double))
        case .unsignedChar: return .unsignedChar(UInt8(double))
        case .unsignedInt: return .unsignedInt(UInt32(double))
        case .unsignedShort: return .unsignedShort(UInt16(double))
        case .unsignedLong: return .unsignedLong(UInt(double))
        case .unsignedLongLong: return .unsignedLongLong(UInt64(double))
        default: return .double(double)
        }
    }

    static func enumValue(from number: NSNumber, attrType: AppViewAttrType) -> AttributeValue {
        switch attrType {
        case .enumLong: return .long(number.intValue)
        default: return .int(Int32(number.intValue))
        }
    }
}

extension Optional where Wrapped == AttributeValue {
    var dashboardDoubleValue: Double { self?.dashboardDoubleValue ?? 0 }
    var dashboardBoolValue: Bool { self?.dashboardBoolValue ?? false }
    var dashboardIntValue: Int { self?.dashboardIntValue ?? 0 }
    var dashboardStringValue: String? { self?.dashboardStringValue }
}

extension NSColor {
    static func lk_colorFromAttributeValue(_ value: AttributeValue?) -> NSColor? {
        guard case .color(let rgba)? = value, rgba.count >= 4 else { return nil }
        return lk_colorFromRGBAComponents(rgba.map { NSNumber(value: $0) })
    }

    func lk_attributeColorValue() -> AttributeValue {
        .color(lk_rgbaComponents().map(\.doubleValue))
    }
}
