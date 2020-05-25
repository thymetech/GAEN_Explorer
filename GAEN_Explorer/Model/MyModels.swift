//
//  MyModels.swift
//
//  Created by Bill Pugh on 5/11/20.
///

import ExposureNotification
import Foundation

func daysAgo(_ days: Int) -> Date { Date(timeIntervalSinceNow: TimeInterval(-days * 24 * 60 * 60)) }

// from ENExposureInfo
struct CodableExposureInfo: Codable {
    let id: UUID
    let date: Date
    let duration: Int8 // minutes
    let totalRiskScore: ENRiskScore

    let transmissionRiskLevel: ENRiskLevel
    let attenuationValue: Int8 // attenuation risk level
    let attenuationDurations: [Int16] // minutes
    var attenuationDurationsString: String {
        attenuationDurations.map { String($0) }.joined(separator: "/")
    }

    var attenuationWeightedTime: Int16 {
        let d0 = attenuationDurations[0]
        let d1 = attenuationDurations[1]
        let d2 = attenuationDurations[2]
        let v0 = d0 * Int16(truncating: CodableExposureConfiguration.attenuationLevelLow)
        let v1 = d1 * Int16(truncating: CodableExposureConfiguration.attenuationLevelMedium)
        let v2 = d2 * Int16(truncating: CodableExposureConfiguration.attenuationLevelHigh)

        return v0 + v1 + v2
    }

    var durationSum: Int16 {
        let d0 = attenuationDurations[0]
        let d1 = attenuationDurations[1]
        let d2 = attenuationDurations[2]
        return d0 + d1 + d2
    }

    var calculatedAttenuationValue: Int8 {
        Int8(attenuationWeightedTime / durationSum)
    }

    init(_ info: ENExposureInfo) {
        self.id = UUID()
        self.date = info.date

        self.duration = Int8(info.duration / 60)
        self.totalRiskScore = info.totalRiskScore
        self.transmissionRiskLevel = info.transmissionRiskLevel
        self.attenuationValue = Int8(info.attenuationValue)
        self.attenuationDurations = info.attenuationDurations.map { Int16(truncating: $0) / 60 }

        print("ENExposureInfo:")
        print("  transmissionRiskLevel \(transmissionRiskLevel)")

        print("  attenuationValue \(attenuationValue)")
        print("  attenuationDurations \(attenuationDurations)")

        print("  attenuationWeightedTime \(attenuationWeightedTime)")
        print("  durationSum \(durationSum)")
        print("  calculatedAttenuationValue \(calculatedAttenuationValue)")
        if info.metadata != nil {
            print("  metadata:")
            for (key, value) in info.metadata! {
                print("    \(key) : \(type(of: value)) = \(value)")
            }
        }
        print()
    }

    init(
        date: Date,
        duration: Int8,
        totalRiskScore: ENRiskScore,
        transmissionRiskLevel: ENRiskLevel,
        attenuationValue: Int8,
        attenuationDurations: [Int16]
    ) {
        self.id = UUID()
        self.date = date
        self.duration = duration
        self.totalRiskScore = totalRiskScore
        self.transmissionRiskLevel = transmissionRiskLevel
        self.attenuationValue = attenuationValue
        self.attenuationDurations = attenuationDurations
    }

    static let testData = [CodableExposureInfo(date: daysAgo(3), duration: 25, totalRiskScore: ENRiskScore(42), transmissionRiskLevel: 5, attenuationValue: 5, attenuationDurations: [5, 10, 10])]
}

// from ENTemporaryExposureKey
struct CodableDiagnosisKey: Codable, Equatable {
    let keyData: Data
    let rollingPeriod: ENIntervalNumber
    let rollingStartNumber: ENIntervalNumber
    let transmissionRiskLevel: ENRiskLevel
    let republicationSecret: UInt64? = nil
    init(_ key: ENTemporaryExposureKey, tRiskLevel: ENRiskLevel) {
        self.keyData = key.keyData
        self.rollingPeriod = key.rollingPeriod
        self.rollingStartNumber = key.rollingStartNumber
        self.transmissionRiskLevel = tRiskLevel
        // self.republicationSecret = UInt64.random(in: UInt64.min ... UInt64.max)
    }

    static func exportToURL(package: PackagedKeys) -> URL? {
        guard let encoded = try? JSONEncoder().encode(package) else { return nil }

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        guard let path = documents?.appendingPathComponent("test.diagk") else {
            return nil
        }

        do {
            print(path)
            try encoded.write(to: path, options: .atomicWrite)
            return path
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

// ENExposureConfiguration
struct CodableExposureConfiguration: Codable {
    static let attenuationLevelHigh: NSNumber = 0
    static let attenuationLevelMedium: NSNumber = 6
    static let attenuationLevelLow: NSNumber = 0
    let minimumRiskScore: ENRiskScore
    let attenuationLevelValues: [ENRiskLevelValue]
    let daysSinceLastExposureLevelValues: [ENRiskLevelValue]
    let durationLevelValues: [ENRiskLevelValue]
    let transmissionRiskLevelValues: [ENRiskLevelValue]
    let attenuationDurationThresholds: [Int]

    static func getExposureConfigurationString() -> String {
        """
        {"minimumRiskScore":0,
        "attenuationLevelValues":[\(CodableExposureConfiguration.attenuationLevelHigh), \(CodableExposureConfiguration.attenuationLevelHigh),
            \(CodableExposureConfiguration.attenuationLevelMedium), \(CodableExposureConfiguration.attenuationLevelMedium),
            \(CodableExposureConfiguration.attenuationLevelLow), \(CodableExposureConfiguration.attenuationLevelLow),
            \(CodableExposureConfiguration.attenuationLevelLow), \(CodableExposureConfiguration.attenuationLevelLow)],
        "daysSinceLastExposureLevelValues":[1, 1, 1, 1, 1, 1, 1, 1],
        "durationLevelValues":[1, 1, 1, 5, 5, 5, 5, 5],
        "transmissionRiskLevelValues":[1, 1, 1, 1, 1, 1, 1, 1],
        "attenuationDurationThresholds": [\(CodableExposureConfiguration.cutoff0), \(CodableExposureConfiguration.cutoff1)]}
        """
    }

    static func getCodableExposureConfiguration() -> CodableExposureConfiguration {
        let dataFromServer = getExposureConfigurationString().data(using: .utf8)!

        let codableExposureConfiguration = try! JSONDecoder().decode(CodableExposureConfiguration.self, from: dataFromServer)
        return codableExposureConfiguration
    }

    static let shared = getCodableExposureConfiguration()
    static let cutoff0 = 50
    static let cutoff1 = 55
    static let attenuationDurationThresholdsKey = "attenuationDurationThresholds"

    func asExposureConfiguration() -> ENExposureConfiguration {
        let exposureConfiguration = ENExposureConfiguration()
        exposureConfiguration.minimumRiskScore = minimumRiskScore
        exposureConfiguration.attenuationLevelValues = attenuationLevelValues as [NSNumber]
        exposureConfiguration.daysSinceLastExposureLevelValues = daysSinceLastExposureLevelValues as [NSNumber]

        exposureConfiguration.durationLevelValues = durationLevelValues as [NSNumber]
        exposureConfiguration.transmissionRiskLevelValues = transmissionRiskLevelValues as [NSNumber]

        exposureConfiguration.attenuationDurationThresholds = [attenuationDurationThresholds[0], attenuationDurationThresholds[1]]

        return exposureConfiguration
    }
}

struct PackagedKeys: Codable {
    var userName: String
    var date: Date
    var keys: [CodableDiagnosisKey]
}

struct BatchExposureInfo: Codable {
    static let exposureDateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"

        return formatter
    }()

    let userName: String
    let dateKeysSent: Date
    let dateProcessed: Date
    var memo: String?
    var config: CodableExposureConfiguration?
    let exposures: [CodableExposureInfo]
    var memoConfig: String {
        if memo != nil {
            return memo!
        }
        if config != nil {
            return "ADT: \(config!.attenuationDurationThresholds[0])/\(config!.attenuationDurationThresholds[1])"
        }
        return ""
    }

    static var testData = BatchExposureInfo(userName: "Bob", dateKeysSent: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60), dateProcessed: Date(),
                                            config: CodableExposureConfiguration.shared, exposures: CodableExposureInfo.testData)
}

class LocalStore: ObservableObject {
    static let shared = LocalStore()

    let userNameKey = "userName"

    @Published
    var userName: String = ""

    @Published
    var viewShown: String? = nil
    let allExposuresKey = "allExposures"

    @Published
    var allExposures: [BatchExposureInfo] = []
    func deleteAllExposures() {
        print("Deleting all exposures")
        allExposures = []
        if let encoded = try? JSONEncoder().encode(allExposures) {
            UserDefaults.standard.set(encoded, forKey: allExposuresKey)
        }
        objectWillChange.send()
    }

    func appendExposure(_ e: BatchExposureInfo) {
        allExposures.append(e)
        if let encoded = try? JSONEncoder().encode(allExposures) {
            UserDefaults.standard.set(encoded, forKey: allExposuresKey)
        }

        objectWillChange.send()
    }

    init(userName: String, transmissionRiskLevel: Int) {
        self.userName = userName
        self.transmissionRiskLevel = transmissionRiskLevel
        self.allExposures = [BatchExposureInfo.testData]
    }

    let transmissionRiskLevelKey = "transmissionRiskLevel"
    @Published
    var transmissionRiskLevel: Int = 5

    init() {
        if let data = UserDefaults.standard.string(forKey: userNameKey) {
            self.userName = data
        }
        if let e = UserDefaults.standard.object(forKey: allExposuresKey) as? Data,
            let loadedExposures = try? JSONDecoder().decode([BatchExposureInfo].self, from: e) {
            self.allExposures = loadedExposures
        }

        let t = UserDefaults.standard.integer(forKey: transmissionRiskLevelKey)

        transmissionRiskLevel = t == 0 ? 5 : t - 1
    }

    var shareExposuresURL: URL?

    func exportExposuresToURL() {
        shareExposuresURL = nil
        guard let encoded = try? JSONEncoder().encode(allExposures) else { return }

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        guard let path = documents?.appendingPathComponent("exposures.json") else {
            return
        }

        do {
            print(path)
            try encoded.write(to: path, options: .atomicWrite)
            shareExposuresURL = path
        } catch {
            print(error.localizedDescription)
            return
        }
    }

    func save() {
        UserDefaults.standard.set(transmissionRiskLevel, forKey: transmissionRiskLevelKey)
        UserDefaults.standard.set(userName, forKey: userNameKey)
        print("User default saved")
    }
}
