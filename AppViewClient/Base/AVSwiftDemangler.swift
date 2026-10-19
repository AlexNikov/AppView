//
//  AVSwiftDemangler.swift
//  AppViewClient
//

import Foundation

public class AVSwiftDemangler: NSObject {
    private static var simpleCache: [String:String] = [:]
    private static var completedCache: [String:String] = [:]
    
    /// 这里返回的结果会尽可能地短，去除了很多信息
    public static func simpleParse(input: String) -> String {
        if let cachedResult = simpleCache[input] {
            return cachedResult
        }
        let result: String
        do {
            let swiftSymbol = try parseMangledSwiftSymbol(input)
            result = swiftSymbol.print(using: [.synthesizeSugarOnTypes, .shortenPartialApply, .shortenThunk, .shortenValueWitness, .shortenArchetype])
        } catch _ {
            result = input
        }
        simpleCache[input] = result
        return result
    }
    
    /// 这里返回的结果会尽可能地长、包含了 module name 等各种信息
    public static func completedParse(input: String) -> String {
        if let cachedResult = completedCache[input] {
            return cachedResult
        }
        let result: String
        do {
            let swiftSymbol = try parseMangledSwiftSymbol(input)
            result = swiftSymbol.print(using: [.displayDebuggerGeneratedModule, .qualifyEntities, .displayExtensionContexts, .displayUnmangledSuffix, .displayModuleNames, .displayGenericSpecializations, .displayProtocolConformances, .displayWhereClauses, .displayEntityTypes, .showPrivateDiscriminators, .showFunctionArgumentTypes])
        } catch _ {
            result = input
        }
        completedCache[input] = result
        return result
    }

    /// `Module.Type` → `Module` and `Type` on separate lines. Dots inside generic arguments or tuples stay.
    public static func lineSeparatedQualifiedName(_ name: String) -> String {
        var depth = 0
        var result = ""
        for character in name {
            switch character {
            case "<", "(", "[":
                depth += 1
                result.append(character)
            case ">", ")", "]":
                depth = max(0, depth - 1)
                result.append(character)
            case "." where depth == 0:
                result.append("\n")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Demangle then split `Module.Type` across lines for dashboard display.
    public static func displayQualifiedName(input: String) -> String {
        lineSeparatedQualifiedName(completedParse(input: input))
    }
}
