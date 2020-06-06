//
//  ExposureAnalysis.swift
//  GAEN_Explorer
//
//  Created by Bill on 5/28/20.
//  Copyright © 2020 Ninja Monkey Coders. All rights reserved.
//

import ExposureNotification
import Foundation

struct ExposureKey: Hashable, CustomStringConvertible {
    var description: String {
        day
    }

    let transmissionRiskLevel: ENRiskLevel

    var date: Date
    var day: String {
        ExposureFramework.shared.dayFormatter.string(from: date)
    }

    init(info: CodableExposureInfo) {
        self.date = info.date
        self.transmissionRiskLevel = info.transmissionRiskLevel
    }
}
// 44, 47, 50, 53, 56, 59, 62, 65
let multipassThresholds = [50, 56,   44, 53,   59, 65,  47, 62]

let numberAnalysisPasses = multipassThresholds.count / 2

func getAttenuationDurationThresholds(pass: Int) -> [Int] {
    [multipassThresholds[2 * (pass - 1)], multipassThresholds[2 * (pass - 1) + 1]]
}
