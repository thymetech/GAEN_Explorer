//
//  SensorFusion.swift
//  GAEN Explorer
//
//  Created by Bill on 6/7/20.
//  Copyright © 2020 NinjaMonkeyCoders. All rights reserved.
//

import CoreMotion
import Foundation

func getTimeFormatter() -> DateFormatter {
    let timeFormatter = DateFormatter()

    timeFormatter.timeStyle = .long
    return timeFormatter
}

enum Activity: String {
    case off
    case faceup
    case facedown
    case stationary
    case walking
    case moving
    case unknown

    static func get(_ cmActivity: CMMotionActivity?, _ hMode: HorizontalMode, _ scanningOn: Bool) -> Activity {
        if !scanningOn {
            return .off
        }
        switch hMode {
        case .faceup:
            return .faceup
        case .facedown:
            return .facedown
        default:
            guard let cmA = cmActivity else { return .unknown }
            if cmA.stationary { return .stationary }
            if cmA.running || cmA.cycling || cmA.automotive { return .moving }
            return .unknown
        }
    }
}

enum SensorReading {
    case scanning(Bool)
    case motion(CMMotionActivity)
    case horizontal(HorizontalMode)
}

struct SensorData {
    let at: Date
    var time: String {
        getTimeFormatter().string(from: at)
    }

    let sensor: SensorReading
}

struct FusedData: Hashable {
    let at: Date
    var time: String {
        getTimeFormatter().string(from: at)
    }

    let activity: Activity
}

extension CMSensorDataList: Sequence {
    public typealias Iterator = NSFastEnumerationIterator
    public func makeIterator() -> NSFastEnumerationIterator {
        NSFastEnumerationIterator(self)
    }
}

enum HorizontalMode {
    static func get(_ a: CMAcceleration) -> HorizontalMode {
        let az = abs(a.z)
        guard a.x * a.x + a.y * a.y < 0.1, az < 1.05, az > 0.9 else {
            return .unknown
        }
        if a.z > 0 {
            return .facedown
        }
        return .faceup
    }

    case unknown
    case faceup
    case facedown
    case invalid
}

struct HoritzontalState {
    let at: Date
    let status: HorizontalMode
}

class SensorFusion {
    static let shared = SensorFusion()

    private let analyzeMotionQueue = DispatchQueue(label: "com.ninjamonkeycoders.gaen.analyzeMotion", attributes: .concurrent)

    let motionActivityManager = CMMotionActivityManager()
    let motionManager = CMMotionManager()

    let pedometer = CMPedometer()

    @Published
    var sensorRecorder: CMSensorRecorder?

    func startAccel() {
        if CMSensorRecorder.isAccelerometerRecordingAvailable() {
            print("accelerometerRecordingAvailable")
            sensorRecorder = CMSensorRecorder()
            print("startAccel")
            analyzeMotionQueue.async {
                self.sensorRecorder!.recordAccelerometer(forDuration: 2 * 60 * 60) // Record for 20 minutes
                print("started recording")
            }
        }
    }

    static let minimumNumberOfSecondsToRecord: TimeInterval = 5

    private func fuseMotionData(_ sensorData: [SensorData],
                                _ motions: [CMMotionActivity],
                                _ results: ([FusedData]?, [Activity: TimeInterval]?) -> Void) {
        var motionData: [SensorData] = motions.map { motion in SensorData(at: motion.startDate, sensor: SensorReading.motion(motion)) }
        print("Have \(motionData.count) motion readings")
        motionData.append(contentsOf: sensorData)

        var accel: CMMotionActivity?
        var scanning = true
        var horizontalMode: HorizontalMode = .unknown
        var fusedData: [FusedData] = []

        var activityDurations: [Activity: TimeInterval] = [:]
        motionData.sorted { $0.at < $1.at }.forEach { sensorData in
            switch sensorData.sensor {
            case let .scanning(isOn):
                scanning = isOn
            case let .motion(cmmActivity):
                accel = cmmActivity
            case let .horizontal(hMode):
                horizontalMode = hMode
            }
            let newActivity = Activity.get(accel, horizontalMode, scanning)
            let fused = FusedData(at: sensorData.at, activity: newActivity)

            if fusedData.count == 0 {
                fusedData.append(fused)
            } else if newActivity != fusedData.last!.activity {
                if fusedData.last!.at.addingTimeInterval(SensorFusion.minimumNumberOfSecondsToRecord) > sensorData.at {
                    if fusedData.count - 2 >= 0, fusedData[fusedData.count - 2].activity == fused.activity {
                        fusedData.remove(at: fusedData.count - 1)
                    } else {
                        fusedData[fusedData.count - 1] = fused
                    }
                } else {
                    fusedData.append(fused)
                }
            }
        }
        print("Got \(fusedData.count) fused data items")

        var prevTime: Date?
        fusedData.forEach { fd in
            if let prev = prevTime {
                let oldTime: TimeInterval = activityDurations[fd.activity] ?? 0
                activityDurations[fd.activity] = oldTime + fd.at.timeIntervalSince(prev)
            }
            prevTime = fd.at
        }

        print("Got \(fusedData.count) fused data items")

        print("activity durations")
        for (key, value) in activityDurations {
            print("  \(key) \(Int(value))")
        }
        results(fusedData, activityDurations)
    }

    static let secondsNeededToRecognizeHorizontal: TimeInterval = 20
    func getSensorData(from: Date, to: Date, results: @escaping ([FusedData]?, [Activity: TimeInterval]?) -> Void) {
        analyzeMotionQueue.async {
            if self.sensorRecorder != nil {
                print("sensor recorded present")
            }
            var horiztonalData: [SensorData] = []
            if let sensor = self.sensorRecorder,
                let data = sensor.accelerometerData(from: from, to: to) {
                print("Got accel")

                var oldHorizontal: HorizontalMode = .invalid
                var startedHorizontal: Date?

                for datum in data {
                    if let accdatum = datum as? CMRecordedAccelerometerData {
                        let horizontal = HorizontalMode.get(accdatum.acceleration)
                        if oldHorizontal != horizontal {
                            if horizontal == .unknown {
                                if let sh = startedHorizontal {
                                    if sh.addingTimeInterval(SensorFusion.secondsNeededToRecognizeHorizontal) < accdatum.startDate {
                                        horiztonalData.append(SensorData(at: sh, sensor: SensorReading.horizontal(oldHorizontal)))
                                        startedHorizontal = nil
                                        horiztonalData.append(SensorData(at: accdatum.startDate, sensor: SensorReading.horizontal(horizontal)))
                                    }
                                } else if horiztonalData.isEmpty {
                                    horiztonalData.append(SensorData(at: accdatum.startDate, sensor: SensorReading.horizontal(horizontal)))
                                }

                            } else {
                                // faceup or facedown
                                startedHorizontal = accdatum.startDate
                            }
                        }
                        oldHorizontal = horizontal
                    }
                }

                if let sh = startedHorizontal {
                    if sh.addingTimeInterval(SensorFusion.secondsNeededToRecognizeHorizontal) < Date() {
                        horiztonalData.append(SensorData(at: sh, sensor: SensorReading.horizontal(oldHorizontal)))
                        startedHorizontal = nil
                    }
                }

                print("Got \(horiztonalData.count) sensor data in horizontal history")

                self.motionActivityManager.queryActivityStarting(from: from,
                                                                 to: to,
                                                                 to: OperationQueue.main) { activities, _ in
                    guard let a = activities else {
                        results(nil, nil)
                        return
                    }
                    self.fuseMotionData(horiztonalData, a, results)
                }
            }
        }
    }
}