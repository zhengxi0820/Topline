import Foundation

/// 歌词源共享的 HTTP 基础设施。
/// 酷狗与网易云的接口都是无鉴权的 web API，带浏览器特征头更稳。
private let lyricsUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

private func request<T: Decodable>(
    _ type: T.Type, _ url: URL, _ session: URLSession,
    completion: @escaping (Result<T, Error>) -> Void
) {
    var req = URLRequest(url: url)
    req.setValue(lyricsUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("https://\(url.host ?? "")/", forHTTPHeaderField: "Referer")
    session.dataTask(with: req) { data, _, error in
        if let error {
            completion(.failure(error))
            return
        }
        guard let data, let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            completion(.failure(URLError(.cannotParseResponse)))
            return
        }
        completion(.success(decoded))
    }.resume()
}

// MARK: - 酷狗（主源）

struct KugouSearchResponse: Codable {
    struct Candidate: Codable {
        let id: String
        let accesskey: String
        let singer: String?
        let song: String?
        /// 毫秒
        let duration: Int?
    }

    let candidates: [Candidate]?
}

struct KugouDownloadResponse: Codable {
    /// base64 编码的 LRC 歌词
    let content: String?
}

extension KugouSearchResponse.Candidate {
    /// 绑定重放凭据与展示信息（标题/歌手缺失时为空串，列表展示时由调用方兜底）
    var versionDescription: LyricVersion {
        LyricVersion(
            source: .kugou,
            title: song ?? "",
            artist: singer ?? "",
            durationMS: duration,
            payload: "\(id)|\(accesskey)"
        )
    }
}

enum KugouLyricsSource {
    static let host = "lyrics.kugou.com"

    /// 搜索并下载，任意一步失败即整体失败（调用方负责回退下一源）。回调线程任意。
    /// 第二个参数为解析出的版本描述（成功时非 nil），供列表窗与绑定记录。
    static func fetch(
        track: TrackState, session: URLSession,
        completion: @escaping ([LyricLine]?, LyricVersion?) -> Void
    ) {
        searchCandidates(track: track, session: session) { candidates in
            guard let candidate = pickCandidate(
                from: candidates,
                title: track.title,
                artist: track.artist,
                duration: track.duration
            ) else {
                completion(nil, nil)
                return
            }
            download(id: candidate.id, accesskey: candidate.accesskey, session: session) { lines in
                completion(lines, candidate.versionDescription)
            }
        }
    }

    /// 仅搜索不下载
    static func searchCandidates(
        track: TrackState, session: URLSession,
        completion: @escaping ([KugouSearchResponse.Candidate]) -> Void
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "keyword", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "duration", value: String(Int(track.duration * 1000))),
        ]
        guard let url = components.url else {
            completion([])
            return
        }
        request(KugouSearchResponse.self, url, session) { result in
            if case .success(let response) = result {
                completion(response.candidates ?? [])
            } else {
                completion([])
            }
        }
    }

    static func download(
        id: String, accesskey: String, session: URLSession,
        completion: @escaping ([LyricLine]?) -> Void
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/download"
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "accesskey", value: accesskey),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        request(KugouDownloadResponse.self, url, session) { result in
            switch result {
            case .success(let response):
                guard let base64 = response.content,
                      let data = Data(base64Encoded: base64),
                      let lrc = String(data: data, encoding: .utf8)
                else {
                    completion(nil)
                    return
                }
                let parsed = LRCParser.parse(lrc)
                completion(parsed.isEmpty ? nil : parsed)
            case .failure:
                completion(nil)
            }
        }
    }

    /// 候选打分挑选：歌名/歌手匹配优先（同歌不同版本时长会有出入），时长按接近度分档。
    /// 实测存在候选时长与实际相差 11 秒仍正确的情况，不能用窄阈值硬过滤。纯函数便于单测。
    static func pickCandidate(
        from candidates: [KugouSearchResponse.Candidate],
        title: String,
        artist: String,
        duration: Double
    ) -> KugouSearchResponse.Candidate? {
        guard !candidates.isEmpty else { return nil }
        let durationMs = duration * 1000

        func nameScore(_ c: KugouSearchResponse.Candidate) -> Int {
            let songHit = c.song.map {
                $0.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains($0)
            } ?? false
            let singerHit = !artist.isEmpty && (c.singer.map {
                $0.localizedCaseInsensitiveContains(artist) || artist.localizedCaseInsensitiveContains($0)
            } ?? false)
            return (songHit ? 2 : 0) + (singerHit ? 1 : 0)
        }

        func durationScore(_ c: KugouSearchResponse.Candidate) -> Int {
            guard let d = c.duration else { return 0 }
            let diff = abs(Double(d) - durationMs)
            if diff <= 5000 { return 3 }
            if diff <= 15000 { return 2 }
            if diff <= 30000 { return 1 }
            return 0
        }

        var bestIndex = 0
        var bestScore = (nameScore(candidates[0]), durationScore(candidates[0]))
        for (index, candidate) in candidates.enumerated().dropFirst() {
            let score = (nameScore(candidate), durationScore(candidate))
            // 同分保序：只接受严格更优的候选
            if score.0 > bestScore.0 || (score.0 == bestScore.0 && score.1 > bestScore.1) {
                bestIndex = index
                bestScore = score
            }
        }
        return candidates[bestIndex]
    }
}

// MARK: - 网易云（回退源）

struct NeteaseSearchResponse: Codable {
    struct Song: Codable {
        struct Artist: Codable { let name: String }
        let id: Int
        let name: String
        let artists: [Artist]
        /// 毫秒
        let duration: Int
    }

    struct ResultBlock: Codable { let songs: [Song]? }
    let result: ResultBlock?
}

struct NeteaseLyricResponse: Codable {
    struct LrcBlock: Codable { let lyric: String? }
    let lrc: LrcBlock?
}

enum NeteaseLyricsSource {
    static let host = "music.163.com"

    /// 搜索并下载。回调线程任意；成功时附带版本描述。
    static func fetch(
        track: TrackState, session: URLSession,
        completion: @escaping ([LyricLine]?, LyricVersion?) -> Void
    ) {
        searchSongs(track: track, session: session) { songs in
            guard let song = pickSong(from: songs, title: track.title, artist: track.artist, duration: track.duration) else {
                completion(nil, nil)
                return
            }
            lyric(id: song.id, session: session) { lines in
                completion(lines, song.versionDescription)
            }
        }
    }

    /// 仅搜索不下载
    static func searchSongs(
        track: TrackState, session: URLSession,
        completion: @escaping ([NeteaseSearchResponse.Song]) -> Void
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/search/get"
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url else {
            completion([])
            return
        }
        request(NeteaseSearchResponse.self, url, session) { result in
            if case .success(let response) = result {
                completion(response.result?.songs ?? [])
            } else {
                completion([])
            }
        }
    }

    static func lyric(
        id: Int, session: URLSession,
        completion: @escaping ([LyricLine]?) -> Void
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/song/lyric"
        components.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }
        request(NeteaseLyricResponse.self, url, session) { result in
            guard case .success(let response) = result,
                  let lrc = response.lrc?.lyric
            else {
                completion(nil)
                return
            }
            let parsed = LRCParser.parse(lrc)
            completion(parsed.isEmpty ? nil : parsed)
        }
    }

    /// 时长最接近优先；歌手不匹配施加大幅罚分（搜索结果常混入翻唱/Live 版）。
    /// 罚分取 60 秒量级：小于典型翻唱版时长差，又足以压过同曲小差异。纯函数便于单测。
    static func pickSong(
        from songs: [NeteaseSearchResponse.Song],
        title: String,
        artist: String,
        duration: Double
    ) -> NeteaseSearchResponse.Song? {
        guard !songs.isEmpty else { return nil }
        func cost(_ s: NeteaseSearchResponse.Song) -> Double {
            let durationDiff = abs(Double(s.duration) - duration * 1000)
            let artistHit = artist.isEmpty || s.artists.contains { a in
                a.name.localizedCaseInsensitiveContains(artist) || artist.localizedCaseInsensitiveContains(a.name)
            }
            return durationDiff + (artistHit ? 0 : 60_000)
        }
        return songs.min(by: { cost($0) < cost($1) })
    }
}

extension NeteaseSearchResponse.Song {
    var versionDescription: LyricVersion {
        LyricVersion(
            source: .netease,
            title: name,
            artist: artists.map(\.name).joined(separator: "/"),
            durationMS: duration,
            payload: String(id)
        )
    }
}
