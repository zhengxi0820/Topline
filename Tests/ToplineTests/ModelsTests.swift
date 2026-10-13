import Foundation
import Testing
@testable import Topline

struct ModelsTests {
    /// 2026-10-12 实机抓包的适配器输出原文
    static let realAdapterJSON = """
    {"artist":"孙燕姿","timestamp":"2026-10-12T05:55:48Z","contentItemIdentifier":"8D3FD6A7-D502-4DC9-9260-08FF11D813BC","title":"开始懂了","elapsedTime":0.032000001519918442,"bundleIdentifier":"com.kugou.mac.Music","playing":true,"processIdentifier":616,"duration":271.49200439453125,"playbackRate":1,"album":"我要的幸福"}
    """

    @Test func decodeRealAdapterOutput() throws {
        let info = try JSONDecoder().decode(NowPlayingInfo.self, from: Data(Self.realAdapterJSON.utf8))
        #expect(info.title == "开始懂了")
        #expect(info.artist == "孙燕姿")
        #expect(info.bundleIdentifier == "com.kugou.mac.Music")
        #expect(info.playing == true)
        #expect(abs((info.duration ?? 0) - 271.492) < 0.001)
        #expect(info.sampledAt != nil)
    }

    @Test func trackStateFromInfo() throws {
        let info = try JSONDecoder().decode(NowPlayingInfo.self, from: Data(Self.realAdapterJSON.utf8))
        let state = try #require(TrackState.from(info))
        #expect(state.title == "开始懂了")
        #expect(state.artist == "孙燕姿")
        #expect(state.album == "我要的幸福")
        #expect(state.isPlaying)
        #expect(state.rate == 1)
        #expect(abs(state.elapsed - 0.032) < 0.001)
        #expect(state.songKey == "开始懂了\u{1}孙燕姿\u{1}271")
    }

    @Test func trackStateRequiresTitle() {
        let noTitle = NowPlayingInfo(
            title: nil, artist: "x", album: nil, duration: nil,
            elapsedTime: nil, playing: nil, playbackRate: nil,
            timestamp: nil, bundleIdentifier: nil
        )
        #expect(TrackState.from(noTitle) == nil)
        let blankTitle = NowPlayingInfo(
            title: "   ", artist: nil, album: nil, duration: nil,
            elapsedTime: nil, playing: nil, playbackRate: nil,
            timestamp: nil, bundleIdentifier: nil
        )
        #expect(TrackState.from(blankTitle) == nil)
    }

    @Test func elapsedInterpolationWhilePlaying() {
        let state = TrackState(
            title: "t", artist: "a", album: nil, duration: 100,
            isPlaying: true, rate: 1,
            elapsed: 10, sampledAt: Date(timeIntervalSince1970: 1000)
        )
        #expect(abs(state.currentElapsed(at: Date(timeIntervalSince1970: 1002.5)) - 12.5) < 0.001)
    }

    @Test func elapsedFrozenWhilePaused() {
        let state = TrackState(
            title: "t", artist: "a", album: nil, duration: 100,
            isPlaying: false, rate: 1,
            elapsed: 10, sampledAt: Date(timeIntervalSince1970: 1000)
        )
        #expect(abs(state.currentElapsed(at: Date(timeIntervalSince1970: 1099)) - 10) < 0.001)
    }

    @Test func elapsedRespectsPlaybackRate() {
        let state = TrackState(
            title: "t", artist: "a", album: nil, duration: 100,
            isPlaying: true, rate: 2,
            elapsed: 10, sampledAt: Date(timeIntervalSince1970: 1000)
        )
        #expect(abs(state.currentElapsed(at: Date(timeIntervalSince1970: 1003)) - 16) < 0.001)
    }
}
