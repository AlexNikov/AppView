//
//  NSString+Score.swift
//
//  Created by Nicholas Bruning on 5/12/11.
//  Copyright (c) 2011 Involved Pty Ltd. All rights reserved.
//

import Foundation

struct NSStringScoreOption: OptionSet {
    let rawValue: UInt

    static let none = NSStringScoreOption([])
    static let favorSmallerWords = NSStringScoreOption(rawValue: 1 << 1)
    static let reducedLongStringPenalty = NSStringScoreOption(rawValue: 1 << 2)
}

extension String {
    func score(against otherString: String) -> CGFloat {
        score(against: otherString, fuzziness: nil)
    }

    func score(against otherString: String, fuzziness: NSNumber?) -> CGFloat {
        score(against: otherString, fuzziness: fuzziness, options: .none)
    }

    func score(against anotherString: String, fuzziness: NSNumber?, options: NSStringScoreOption) -> CGFloat {
        let invalidCharacterSet = invalidCharacterSetForScore()
        let decomposed = decomposedString(invalidCharacterSet: invalidCharacterSet)
        return score(
            against: anotherString,
            fuzziness: fuzziness,
            options: options,
            invalidCharacterSet: invalidCharacterSet,
            decomposedString: decomposed
        )
    }

    func score(
        against anotherString: String,
        fuzziness: NSNumber?,
        options: NSStringScoreOption,
        invalidCharacterSet: CharacterSet,
        decomposedString string: String
    ) -> CGFloat {
        let otherString = anotherString
            .decomposedStringWithCanonicalMapping
            .components(separatedBy: invalidCharacterSet)
            .joined()

        if string == otherString { return 1 }
        if otherString.isEmpty { return 0 }

        var totalCharacterScore: CGFloat = 0
        let otherStringLength = otherString.count
        let stringLength = string.count
        var startOfStringBonus = false
        var fuzzies: CGFloat = 1
        let finalScore: CGFloat

        let otherUpper = otherString.uppercased()
        let otherLower = otherString.lowercased()
        let fuzzinessFloat = fuzziness?.floatValue ?? 0
        let space: Character = " "

        var remaining = string
        for index in 0..<otherStringLength {
            var characterScore: CGFloat = 0.1
            var indexInString: Int?

            let chrIndex = otherString.index(otherString.startIndex, offsetBy: index)
            let chr = otherString[chrIndex]
            let upperChr = String(otherUpper[chrIndex])
            let lowerChr = String(otherLower[chrIndex])

            let rangeChrLowercase = remaining.range(of: lowerChr)
            let rangeChrUppercase = remaining.range(of: upperChr)

            if rangeChrLowercase == nil && rangeChrUppercase == nil {
                if fuzziness != nil {
                    fuzzies += 1 - CGFloat(fuzzinessFloat)
                } else {
                    return 0
                }
            } else if rangeChrLowercase != nil && rangeChrUppercase != nil {
                let lowerIdx = remaining.distance(from: remaining.startIndex, to: rangeChrLowercase!.lowerBound)
                let upperIdx = remaining.distance(from: remaining.startIndex, to: rangeChrUppercase!.lowerBound)
                indexInString = min(lowerIdx, upperIdx)
            } else if let range = rangeChrLowercase ?? rangeChrUppercase {
                indexInString = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
            }

            if let indexInString,
               indexInString < remaining.count {
                let remainingIndex = remaining.index(remaining.startIndex, offsetBy: indexInString)
                if remaining[remainingIndex] == chr {
                    characterScore += 0.1
                }
            }

            if indexInString == 0 {
                characterScore += 0.6
                if index == 0 {
                    startOfStringBonus = true
                }
            } else if let indexInString,
                      indexInString > 0 {
                let prevIndex = remaining.index(remaining.startIndex, offsetBy: indexInString - 1)
                if remaining[prevIndex] == space {
                    characterScore += 0.8
                }
            }

            if let indexInString {
                let cutIndex = remaining.index(remaining.startIndex, offsetBy: indexInString + 1)
                remaining = String(remaining[cutIndex...])
            }

            totalCharacterScore += characterScore
        }

        if options.contains(.favorSmallerWords) {
            return totalCharacterScore / CGFloat(stringLength)
        }

        let otherStringScore = totalCharacterScore / CGFloat(otherStringLength)

        if options.contains(.reducedLongStringPenalty) {
            let percentageOfMatchedString = CGFloat(otherStringLength) / CGFloat(stringLength)
            let wordScore = otherStringScore * percentageOfMatchedString
            finalScore = (wordScore + otherStringScore) / 2
        } else {
            finalScore = ((otherStringScore * (CGFloat(otherStringLength) / CGFloat(stringLength))) + otherStringScore) / 2
        }

        var result = finalScore / fuzzies
        if startOfStringBonus && result + 0.15 < 1 {
            result += 0.15
        }
        return result
    }

    private func invalidCharacterSetForScore() -> CharacterSet {
        var working = CharacterSet.lowercaseLetters
        working.formUnion(.uppercaseLetters)
        working.insert(charactersIn: " ")
        return working.inverted
    }

    private func decomposedString(invalidCharacterSet: CharacterSet) -> String {
        decomposedStringWithCanonicalMapping
            .components(separatedBy: invalidCharacterSet)
            .joined()
    }
}

extension NSString {
    func scoreAgainst(_ otherString: String) -> CGFloat {
        (self as String).score(against: otherString)
    }

    func scoreAgainst(_ otherString: String, fuzziness: NSNumber?) -> CGFloat {
        (self as String).score(against: otherString, fuzziness: fuzziness)
    }

    func scoreAgainst(_ otherString: String, fuzziness: NSNumber?, options: UInt) -> CGFloat {
        (self as String).score(against: otherString, fuzziness: fuzziness, options: NSStringScoreOption(rawValue: options))
    }
}
