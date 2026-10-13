import Foundation
import Testing
@testable import Topline

struct LyricsSourceTests {
    /// 2026-10-12 实机抓包的酷狗搜索响应节选
    static let kugouSearchJSON = """
    {"status":200,"info":"OK","keyword":"开始懂了 孙燕姿","candidates":[{"id":"525046459","accesskey":"E1D14F76BD9CB8BA58124249B81D93D5","singer":"孙燕姿","song":"开始懂了","duration":260000,"uid":"41092797","nickname":"热心用户"}]}
    """

    /// 2026-10-12 实机抓包的网易云搜索响应节选
    static let neteaseSearchJSON = """
    {"result":{"songs":[{"id":2652820720,"name":"晴天(深情版)","duration":278961,"artists":[{"id":50489121,"name":"Lucky小爱"}]},{"id":3440441479,"name":"晴天","duration":112373,"artists":[{"id":123,"name":"Jay"}]}]},"code":200}
    """

    @Test func decodeKugouSearchResponse() throws {
        let response = try JSONDecoder().decode(KugouSearchResponse.self, from: Data(Self.kugouSearchJSON.utf8))
        let candidate = try #require(response.candidates?.first)
        #expect(candidate.id == "525046459")
        #expect(candidate.accesskey == "E1D14F76BD9CB8BA58124249B81D93D5")
        #expect(candidate.duration == 260000)
    }

    @Test func decodeNeteaseSearchResponse() throws {
        let response = try JSONDecoder().decode(NeteaseSearchResponse.self, from: Data(Self.neteaseSearchJSON.utf8))
        let songs = try #require(response.result?.songs)
        #expect(songs.count == 2)
        #expect(songs[0].name == "晴天(深情版)")
        #expect(songs[1].artists.first?.name == "Jay")
    }

    // MARK: - 酷狗候选挑选

    private func kugouCandidate(id: String, singer: String? = nil, song: String? = nil, duration: Int? = nil) -> KugouSearchResponse.Candidate {
        KugouSearchResponse.Candidate(id: id, accesskey: "key-\(id)", singer: singer, song: song, duration: duration)
    }

    @Test func kugouPickPrefersNameMatchOverDuration() {
        let candidates = [
            kugouCandidate(id: "wrong", singer: "别人", song: "别的歌", duration: 260000),
            kugouCandidate(id: "right", singer: "孙燕姿", song: "开始懂了", duration: 262000),
        ]
        let picked = KugouLyricsSource.pickCandidate(from: candidates, title: "开始懂了", artist: "孙燕姿", duration: 271.492)
        #expect(picked?.id == "right")
    }

    @Test func kugouPickFallsBackToDurationOnly() {
        let candidates = [
            kugouCandidate(id: "far", singer: "x", song: "y", duration: 300000),
            kugouCandidate(id: "near", singer: "p", song: "q", duration: 268000),
        ]
        let picked = KugouLyricsSource.pickCandidate(from: candidates, title: "开始懂了", artist: "孙燕姿", duration: 271.492)
        #expect(picked?.id == "near")
    }

    @Test func kugouPickFallsBackToFirstWhenNothingMatches() {
        let candidates = [kugouCandidate(id: "only", singer: nil, song: nil, duration: nil)]
        let picked = KugouLyricsSource.pickCandidate(from: candidates, title: "t", artist: "a", duration: 100)
        #expect(picked?.id == "only")
    }

    @Test func kugouPickEmptyReturnsNil() {
        #expect(KugouLyricsSource.pickCandidate(from: [], title: "t", artist: "a", duration: 100) == nil)
    }

    // MARK: - 网易云歌曲挑选

    private func neteaseSong(id: Int, name: String, artist: String, duration: Int) -> NeteaseSearchResponse.Song {
        NeteaseSearchResponse.Song(id: id, name: name, artists: [.init(name: artist)], duration: duration)
    }

    @Test func neteasePickPrefersArtistMatchOverCloserCover() {
        // 翻唱版时长几乎一样，但歌手不对 → 官方版胜出
        let songs = [
            neteaseSong(id: 1, name: "晴天", artist: "GYBeat", duration: 268_750),
            neteaseSong(id: 2, name: "晴天", artist: "周杰伦", duration: 269_283),
        ]
        let picked = NeteaseLyricsSource.pickSong(from: songs, title: "晴天", artist: "周杰伦", duration: 269.0)
        #expect(picked?.id == 2)
    }

    @Test func neteasePickByDurationWhenArtistEmpty() {
        let songs = [
            neteaseSong(id: 1, name: "晴天", artist: "A", duration: 300_000),
            neteaseSong(id: 2, name: "晴天", artist: "B", duration: 269_000),
        ]
        let picked = NeteaseLyricsSource.pickSong(from: songs, title: "晴天", artist: "", duration: 269.0)
        #expect(picked?.id == 2)
    }

    @Test func neteasePickEmptyReturnsNil() {
        #expect(NeteaseLyricsSource.pickSong(from: [], title: "t", artist: "a", duration: 100) == nil)
    }
}
