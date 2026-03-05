import Foundation

struct AppGainStore {
    static let defaultKey = "audio.sessionGain.byBundleID"

    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = defaultKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func gain(for bundleID: String) -> Float? {
        guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let map = userDefaults.dictionary(forKey: key) else {
            return nil
        }
        if let number = map[bundleID] as? NSNumber {
            return clamp(number.floatValue)
        }
        if let value = map[bundleID] as? Double {
            return clamp(Float(value))
        }
        return nil
    }

    func setGain(_ gain: Float, for bundleID: String) {
        guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        var map = userDefaults.dictionary(forKey: key) ?? [:]
        map[bundleID] = clamp(gain)
        userDefaults.set(map, forKey: key)
    }

    func removeGain(for bundleID: String) {
        guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        var map = userDefaults.dictionary(forKey: key) ?? [:]
        map.removeValue(forKey: bundleID)
        userDefaults.set(map, forKey: key)
    }

    func resetAll() {
        userDefaults.removeObject(forKey: key)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
