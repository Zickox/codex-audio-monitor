import XCTest
@testable import CodexAudioMonitor

final class AppGainStoreTests: XCTestCase {
    func testPersistsGainByBundleIDWithClamp() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.app.gain")

        store.setGain(1.4, for: "com.spotify.client")
        store.setGain(-0.2, for: "com.apple.Safari")

        XCTAssertEqual(store.gain(for: "com.spotify.client"), 1.0)
        XCTAssertEqual(store.gain(for: "com.apple.Safari"), 0.0)
    }

    func testRemoveAndReset() {
        let defaults = makeDefaults()
        let store = AppGainStore(userDefaults: defaults, key: "test.app.gain")

        store.setGain(0.5, for: "com.spotify.client")
        store.setGain(0.7, for: "com.apple.Safari")
        store.removeGain(for: "com.spotify.client")

        XCTAssertNil(store.gain(for: "com.spotify.client"))
        if let safariGain = store.gain(for: "com.apple.Safari") {
            XCTAssertEqual(safariGain, 0.7, accuracy: 0.0001)
        } else {
            XCTFail("Expected persisted gain for Safari")
        }

        store.resetAll()
        XCTAssertNil(store.gain(for: "com.apple.Safari"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppGainStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
