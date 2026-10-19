//
//  AVMeasureResultLineData.swift
//  AppView
//

import Foundation

class AVMeasureResultHorLineData: NSObject {
    var startX: CGFloat = 0
    var endX: CGFloat = 0
    var y: CGFloat = 0
    var displayValue: CGFloat = 0

    static func data(startX: CGFloat, endX: CGFloat, y: CGFloat, value: CGFloat) -> AVMeasureResultHorLineData {
        let data = AVMeasureResultHorLineData()
        data.startX = startX
        data.endX = endX
        data.y = y
        data.displayValue = value
        return data
    }
}

class AVMeasureResultVerLineData: NSObject {
    var startY: CGFloat = 0
    var endY: CGFloat = 0
    var x: CGFloat = 0
    var displayValue: CGFloat = 0

    static func data(startY: CGFloat, endY: CGFloat, x: CGFloat, value: CGFloat) -> AVMeasureResultVerLineData {
        let data = AVMeasureResultVerLineData()
        data.startY = startY
        data.endY = endY
        data.x = x
        data.displayValue = value
        return data
    }
}
