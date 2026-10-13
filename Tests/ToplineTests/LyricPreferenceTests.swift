import Foundation
import Testing
@testable import Topline

struct LyricPreferenceTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "topline-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func bindingRoundtripAndClear() {
        let defaults = freshDefaults()
        let version = LyricVersion(
            source: .kugou, title: "爱如潮水", artist: "张信哲",
            durationMS: 275014, payload: "525046459|E1D14F76"
        )
        #expect(LyricPreference.binding(for: "song-a", defaults: defaults) == nil)
        LyricPreference.setBinding(version, for: "song-a", defaults: defaults)
        #expect(LyricPreference.binding(for: "song-a", defaults: defaults) == version)
        LyricPreference.setBinding(nil, for: "song-a", defaults: defaults)
        #expect(LyricPreference.binding(for: "song-a", defaults: defaults) == nil)
    }

    @Test func timeOffsetDefaultsToZero() {
        let defaults = freshDefaults()
        #expect(LyricPreference.timeOffset(for: "song-a", defaults: defaults) == 0)
    }

    @Test func timeOffsetClampedToFiveSeconds() {
        let defaults = freshDefaults()
        LyricPreference.setTimeOffset(7, for: "song-a", defaults: defaults)
        #expect(LyricPreference.timeOffset(for: "song-a", defaults: defaults) == 5)
        LyricPreference.setTimeOffset(-9, for: "song-a", defaults: defaults)
        #expect(LyricPreference.timeOffset(for: "song-a", defaults: defaults) == -5)
    }

    @Test func timeOffsetZeroRemovesEntry() {
        let defaults = freshDefaults()
        LyricPreference.setTimeOffset(0.6, for: "song-a", defaults: defaults)
        #expect(LyricPreference.timeOffset(for: "song-a", defaults: defaults) == 0.6)
        LyricPreference.setTimeOffset(0, for: "song-a", defaults: defaults)
        #expect(LyricPreference.timeOffset(for: "song-a", defaults: defaults) == 0)
        // 清掉后与其他未设置曲目同域，不残留脏数据
        let all = defaults.data(forKey: LyricPreference.offsetsKey)
        #expect(all == nil || (try? JSONDecoder().decode([String: Double].self, from: all!))?.isEmpty == true)
    }

    @Test func versionCodableRoundtrip() throws {
        let version = LyricVersion(
            source: .localKRC, title: "晴天 (钢琴版)", artist: "庄东茹",
            durationMS: 241_000, payload: "庄东茹 - 晴天 (钢琴版)_24ff1e808c48ced01c0d0bcf701c57c6.krc"
        )
        let data = try JSONEncoder().encode(version)
        let decoded = try JSONDecoder().decode(LyricVersion.self, from: data)
        #expect(decoded == version)
        #expect(decoded.id.contains("本地KRC"))
    }

    @Test func displayFields() {
        let version = LyricVersion(
            source: .netease, title: "晴天", artist: "周杰伦",
            durationMS: 269_283, payload: "12345"
        )
        #expect(version.displayTitle == "周杰伦 — 晴天")
        #expect(version.displayDuration == "4:29")
        let unknown = LyricVersion(
            source: .netease, title: "x", artist: "y", durationMS: nil, payload: "1"
        )
        #expect(unknown.displayDuration == "—")
    }
}
