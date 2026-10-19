//
//  AVLayoutCore.swift
//  AppView
//

import AppKit
import Foundation

enum AVLayoutStorage {
    case object(Any)
    case group([Any])

    var anyValue: Any? {
        switch self {
        case .object(let value):
            return value is NSNull ? nil : value
        case .group(let values):
            return values
        }
    }
}

struct AVLayoutProxy {
    var storage: AVLayoutStorage

    var _get: Any? { storage.anyValue }

    init(wrappedObject: Any?) {
        if let wrapped = wrappedObject {
            storage = .object(wrapped)
        } else {
            storage = .object(NSNull())
        }
    }

    init(storage: AVLayoutStorage) {
        self.storage = storage
    }

    static func make(with object: Any?) -> AVLayoutProxy {
        AVLayoutProxy(wrappedObject: object)
    }

    static func make(with objects: Any?...) -> AVLayoutProxy {
        let values = objects.compactMap { $0 }
        if values.count > 1 {
            return AVLayoutProxy(storage: .group(values))
        }
        return AVLayoutProxy(wrappedObject: values.first)
    }
}

func lkEqualClass(_ object: Any?, _ cls: AnyClass) -> Bool {
    guard let object else { return false }
    return (object as? NSObject)?.isKind(of: cls) ?? false
}

@discardableResult
func lkLayoutMake(_ object: Any?) -> AVLayoutProxy {
    AVLayoutProxy.make(with: object)
}

@discardableResult
func lk(_ object: Any?) -> AVLayoutProxy {
    AVLayoutProxy.make(with: object)
}

@discardableResult
func lk(_ o1: Any?, _ o2: Any?) -> AVLayoutProxy {
    AVLayoutProxy.make(with: o1, o2)
}

@discardableResult
func lk(_ o1: Any?, _ o2: Any?, _ o3: Any?) -> AVLayoutProxy {
    AVLayoutProxy.make(with: o1, o2, o3)
}

@discardableResult
func lk(_ o1: Any?, _ o2: Any?, _ o3: Any?, _ o4: Any?) -> AVLayoutProxy {
    AVLayoutProxy.make(with: o1, o2, o3, o4)
}

extension AVLayoutProxy {
    func unpack(_ classA: AnyClass, do handlerA: @escaping (Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        unpackClassA(classA, doA: handlerA, classB: nil, doB: nil)
    }

    func unpackClassA(
        _ classA: AnyClass,
        doA handlerA: ((Any, UnsafeMutablePointer<ObjCBool>) -> Void)?,
        classB: AnyClass?,
        doB: ((Any, UnsafeMutablePointer<ObjCBool>) -> Void)?
    ) {
        guard let get = _get else { return }

        if let array = get as? [Any] {
            for obj in array {
                if lkEqualClass(obj, classA) {
                    var stop: ObjCBool = false
                    handlerA?(obj, &stop)
                    if stop.boolValue { break }
                } else if let classB, lkEqualClass(obj, classB) {
                    var stop: ObjCBool = false
                    doB?(obj, &stop)
                    if stop.boolValue { break }
                }
            }
        } else {
            var shouldStop: ObjCBool = false
            if lkEqualClass(get, classA) {
                handlerA?(get, &shouldStop)
            } else if let classB, lkEqualClass(get, classB) {
                doB?(get, &shouldStop)
            }
        }
    }

    func filteredGet(_ classes: AnyClass...) -> [Any]? {
        guard !classes.isEmpty else { return nil }
        var filtered: [Any] = []
        let initialGet = _get
        if let array = initialGet as? [Any] {
            for get in array {
                for className in classes {
                    if lkEqualClass(get, className) {
                        filtered.append(get)
                        break
                    }
                }
            }
        } else if let initialGet {
            for className in classes {
                if lkEqualClass(initialGet, className) {
                    filtered.append(initialGet)
                    break
                }
            }
        }
        return filtered.isEmpty ? nil : filtered
    }
}
