import CryptoKit
import Foundation

/// 歌词编排中心。
///
/// 获取优先级：手动绑定版本 → 酷狗本地 KRC → 酷狗网络 → 网易云（自动链）。
/// 缓存键 = songKey + 版本 id，同曲多版本互不覆盖；自动链的缓存无逐字数据时
/// 会被本地 KRC 升级替换。版本绑定与时间偏移经 LyricPreference 持久化。
final class LyricsProvider {
    private let session: URLSession
    /// 本地 KRC 是文件 IO，放串行后台队列，不占网络回调线程
    private let workQueue = DispatchQueue(label: "topline.local", qos: .utility)
    /// 自动链解析出的版本（列表窗打勾用），仅内存
    private var lastAutoVersion: [String: LyricVersion] = [:]
    private var memory: [String: [LyricLine]] = [:]
    private var inflight = Set<String>()
    /// 已交付过结果的曲目，本地延迟重查据此判断是否需要替换网络结果
    private var delivered: Set<String> = []
    private let diskCacheDir: URL

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)

        diskCacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Topline/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 主入口

    /// 完成回调在主线程，同一曲目可能被调用两次（先给低优先级结果、再被本地 KRC 升级替换）；
    /// nil 表示所有源都没拿到。
    func lyrics(for track: TrackState, completion: @escaping ([LyricLine]?) -> Void) {
        let songKey = track.songKey
        if let bound = LyricPreference.binding(for: songKey) {
            resolve(version: bound, track: track, cacheKey: Self.cacheKey(songKey, bound.id), completion: completion)
            return
        }

        let key = Self.cacheKey(songKey, "auto")
        if let cached = memory[key], hasWordTiming(cached) {
            completion(cached)
            return
        }
        if let disk = loadDisk(key), hasWordTiming(disk) {
            DebugLog.log("歌词命中磁盘缓存")
            memory[key] = disk
            completion(disk)
            return
        }
        guard !inflight.contains(key) else { return }
        inflight.insert(key)
        delivered.insert(songKey)

        // 缓存里的网络版词没有逐字数据，先给用户看着，同时看本地 KRC 能否升级
        if let cached = memory[key] ?? loadDisk(key) {
            completion(cached)
            upgradeToKRC(track, key: key, completion: completion)
            return
        }

        func finish(_ lines: [LyricLine]?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inflight.remove(key)
                if let lines {
                    self.memory[key] = lines
                    self.delivered.insert(songKey)
                    self.saveDisk(key, lines)
                }
                completion(lines)
            }
        }

        workQueue.async { [weak self] in
            // 第一优先：酷狗本地 KRC——客户端自己为该音频匹配的词，版本与逐字时间都准
            if let local = KugouLocalSource.bestMatch(for: track) {
                DebugLog.log("歌词来源: 本地KRC (\(local.file.lastPathComponent))")
                self?.recordAuto(LyricVersion(
                    source: .localKRC,
                    title: track.title, artist: track.artist,
                    durationMS: nil, payload: local.file.lastPathComponent
                ), for: songKey)
                finish(local.lines)
                return
            }
            guard let self else { return }
            // 第二/三优先：酷狗网络 → 网易云
            KugouLyricsSource.fetch(track: track, session: self.session) { lines, version in
                if let lines, !lines.isEmpty {
                    DebugLog.log("歌词来源: 酷狗")
                    if let version { self.recordAuto(version, for: songKey) }
                    finish(lines)
                    self.scheduleLocalRetry(track, songKey: songKey, cacheKey: key, completion: completion)
                } else {
                    NeteaseLyricsSource.fetch(track: track, session: self.session) { neteaseLines, neteaseVersion in
                        DebugLog.log(neteaseLines != nil ? "歌词来源: 网易云(回退)" : "歌词未找到: 本地与双网源均无结果")
                        if let neteaseLines, let neteaseVersion {
                            self.recordAuto(neteaseVersion, for: songKey)
                        }
                        finish(neteaseLines)
                        self.scheduleLocalRetry(track, songKey: songKey, cacheKey: key, completion: completion)
                    }
                }
            }
        }
    }

    private func recordAuto(_ version: LyricVersion, for songKey: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastAutoVersion[songKey] = version
        }
    }

    // MARK: - 版本管理（保底 UI 用）

    /// 列出当前曲目的全部候选版本：本地 KRC + 酷狗搜索 + 网易云搜索。回调在主线程。
    func versions(for track: TrackState, completion: @escaping ([LyricVersion]) -> Void) {
        let mergeQueue = DispatchQueue(label: "topline.merge")
        var result: [LyricVersion] = []
        var pending = 3

        func collect(_ batch: [LyricVersion]) {
            mergeQueue.async {
                result.append(contentsOf: batch)
                pending -= 1
                if pending == 0 {
                    let localOrder: [LyricVersion.Source] = [.localKRC, .kugou, .netease]
                    let sorted = result.sorted { a, b in
                        let ia = localOrder.firstIndex(of: a.source) ?? 9
                        let ib = localOrder.firstIndex(of: b.source) ?? 9
                        return ia < ib
                    }
                    DispatchQueue.main.async { completion(sorted) }
                }
            }
        }

        workQueue.async {
            let local = KugouLocalSource.versions(title: track.title, artist: track.artist).map { v in
                LyricVersion(source: .localKRC, title: v.title, artist: v.artist, durationMS: v.durationMS, payload: v.url.lastPathComponent)
            }
            collect(local)
        }
        KugouLyricsSource.searchCandidates(track: track, session: session) { candidates in
            collect(candidates.map { Self.version(from: $0, track: track) })
        }
        NeteaseLyricsSource.searchSongs(track: track, session: session) { songs in
            collect(songs.map { Self.version(from: $0) })
        }
    }

    /// 应用用户手选版本：写绑定并解析。失败时回调 nil（绑定保留，下次切歌重试）。
    func applyVersion(_ version: LyricVersion, for track: TrackState, completion: @escaping ([LyricLine]?) -> Void) {
        LyricPreference.setBinding(version, for: track.songKey)
        resolve(version: version, track: track, cacheKey: Self.cacheKey(track.songKey, version.id), completion: completion)
    }

    func clearBinding(for songKey: String) {
        LyricPreference.setBinding(nil, for: songKey)
        lastAutoVersion.removeValue(forKey: songKey)
    }

    /// 列表窗打勾依据：绑定优先，其次自动链解析出的版本
    func activeVersionId(for songKey: String) -> String? {
        if let bound = LyricPreference.binding(for: songKey) {
            return bound.id
        }
        return lastAutoVersion[songKey]?.id
    }

    func binding(for songKey: String) -> LyricVersion? {
        LyricPreference.binding(for: songKey)
    }

    /// 该曲是否正在解析途中（自动链或绑定版本）
    func isFetching(_ songKey: String) -> Bool {
        let key = LyricPreference.binding(for: songKey).map { Self.cacheKey(songKey, $0.id) }
            ?? Self.cacheKey(songKey, "auto")
        return inflight.contains(key)
    }

    /// 自动链（或当前绑定）已有缓存结果；nil 表示没有——用于"未找到"提示判定
    func cachedAutoLines(for songKey: String) -> [LyricLine]? {
        let key = LyricPreference.binding(for: songKey).map { Self.cacheKey(songKey, $0.id) }
            ?? Self.cacheKey(songKey, "auto")
        return memory[key] ?? loadDisk(key)
    }

    // MARK: - 时间偏移

    func timeOffset(for songKey: String) -> Double {
        LyricPreference.timeOffset(for: songKey)
    }

    func adjustTimeOffset(by delta: Double, for songKey: String) -> Double {
        let value = LyricPreference.timeOffset(for: songKey) + delta
        LyricPreference.setTimeOffset(value, for: songKey)
        return LyricPreference.timeOffset(for: songKey)
    }

    func resetTimeOffset(for songKey: String) {
        LyricPreference.setTimeOffset(0, for: songKey)
    }

    // MARK: - 版本解析（绑定重放与自动链共用）

    private func resolve(
        version: LyricVersion,
        track: TrackState,
        cacheKey: String,
        completion: @escaping ([LyricLine]?) -> Void
    ) {
        if let cached = memory[cacheKey] {
            completion(cached)
            return
        }
        if let disk = loadDisk(cacheKey) {
            memory[cacheKey] = disk
            completion(disk)
            return
        }
        guard !inflight.contains(cacheKey) else { return }
        inflight.insert(cacheKey)
        delivered.insert(track.songKey)

        func finish(_ lines: [LyricLine]?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inflight.remove(cacheKey)
                if let lines {
                    self.memory[cacheKey] = lines
                    self.saveDisk(cacheKey, lines)
                }
                completion(lines)
            }
        }

        switch version.source {
        case .localKRC:
            workQueue.async { [weak self] in
                guard let self, let dir = KugouLocalSource.cacheDirectory(),
                      let content = try? KRCDecoder.decode(Data(contentsOf: dir.appendingPathComponent(version.payload)))
                else {
                    finish(nil)
                    return
                }
                finish(content.lines)
            }
        case .kugou:
            let parts = version.payload.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                finish(nil)
                return
            }
            KugouLyricsSource.download(
                id: parts[0], accesskey: parts[1], session: session
            ) { lines in
                finish(lines)
            }
        case .netease:
            guard let songId = Int(version.payload) else {
                finish(nil)
                return
            }
            NeteaseLyricsSource.lyric(id: songId, session: session) { lines in
                finish(lines)
            }
        }
    }

    static func cacheKey(_ songKey: String, _ versionId: String) -> String {
        songKey + "\u{2}" + versionId
    }

    static func version(from candidate: KugouSearchResponse.Candidate, track: TrackState) -> LyricVersion {
        LyricVersion(
            source: .kugou,
            title: candidate.song ?? track.title,
            artist: candidate.singer ?? track.artist,
            durationMS: candidate.duration,
            payload: "\(candidate.id)|\(candidate.accesskey)"
        )
    }

    static func version(from song: NeteaseSearchResponse.Song) -> LyricVersion {
        LyricVersion(
            source: .netease,
            title: song.name,
            artist: song.artists.map(\.name).joined(separator: "/"),
            durationMS: song.duration,
            payload: String(song.id)
        )
    }

    // MARK: - 本地 KRC 升级与延迟重查

    private func hasWordTiming(_ lines: [LyricLine]) -> Bool {
        lines.contains { $0.words != nil && !($0.words ?? []).isEmpty }
    }

    /// 缓存命中的是网络版词（无逐字数据）时，尝试用本地 KRC 升级替换
    private func upgradeToKRC(_ track: TrackState, key: String, completion: @escaping ([LyricLine]?) -> Void) {
        workQueue.async { [weak self] in
            guard let local = KugouLocalSource.bestMatch(for: track) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.delivered.contains(track.songKey) else { return }
                DebugLog.log("歌词升级: 网络缓存 -> 本地KRC (\(local.file.lastPathComponent))")
                self.memory[key] = local.lines
                self.saveDisk(key, local.lines)
                self.recordAuto(LyricVersion(
                    source: .localKRC,
                    title: track.title, artist: track.artist,
                    durationMS: nil, payload: local.file.lastPathComponent
                ), for: track.songKey)
                completion(local.lines)
            }
        }
    }

    /// 切歌瞬间酷狗可能还没把 KRC 落盘（网络词只是垫场）；3 秒后重查本地，
    /// 命中则用 KRC 替换网络结果（调用方按 songKey 幂等覆盖）。
    /// 状态读写都在主线程，workQueue 只做文件 IO。
    private func scheduleLocalRetry(
        _ track: TrackState, songKey: String, cacheKey: String,
        completion: @escaping ([LyricLine]?) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.delivered.contains(songKey) else { return }
            self.workQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let local = KugouLocalSource.bestMatch(for: track) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.delivered.contains(songKey) else { return }
                    DebugLog.log("歌词来源: 本地KRC(延迟重查替换) (\(local.file.lastPathComponent))")
                    self.memory[cacheKey] = local.lines
                    self.saveDisk(cacheKey, local.lines)
                    self.recordAuto(LyricVersion(
                        source: .localKRC,
                        title: track.title, artist: track.artist,
                        durationMS: nil, payload: local.file.lastPathComponent
                    ), for: songKey)
                    completion(local.lines)
                }
            }
        }
    }

    // MARK: - 磁盘缓存

    private func cacheFileURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        let readable = key
            .replacingOccurrences(of: "\u{1}", with: " - ")
            .replacingOccurrences(of: "\u{2}", with: " ~ ")
            .prefix(60)
        return diskCacheDir.appendingPathComponent("\(readable).\(digest).json")
    }

    private func loadDisk(_ key: String) -> [LyricLine]? {
        guard let data = try? Data(contentsOf: cacheFileURL(key)) else { return nil }
        return try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    private func saveDisk(_ key: String, _ lines: [LyricLine]) {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: cacheFileURL(key), options: .atomic)
    }
}
