import Foundation

/// 酷狗 Mac 客户端的本地歌词缓存（Caches/kgLyric，文件名 "歌手 - 歌名_文件指纹.krc"）。
/// 这是酷狗自己为正在播放的音频文件匹配的歌词：版本天然正确，且自带逐字时间轴。
/// 目录结构属于酷狗私有实现，随其客户端版本可能变化——路径集中在 cacheDirectory 一处。
enum KugouLocalSource {
    struct Version {
        let url: URL
        let title: String
        let artist: String
        let durationMS: Int?
        let modifiedAt: Date
    }

    /// 返回 nil 表示本机没有酷狗缓存（如朋友机器未装酷狗），调用方直接走网络源
    static func cacheDirectory() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.kugou.mac.Music/Data")
            .appendingPathComponent("Library/Application Support/com.kugou.mac.Music/Caches/kgLyric")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return dir
    }

    /// 文件名匹配（纯函数便于单测）：剥掉 .krc 与 _32位指纹 后缀，
    /// 剩余 "歌手 - 歌名" 需同时包含歌名与歌手（忽略大小写与空格）。
    /// 纯数字命名的缓存文件无法按名匹配，跳过（不做全量解码索引，保持轻量）。
    static func filenameMatches(_ filename: String, title: String, artist: String) -> Bool {
        var name = filename
        if name.hasSuffix(".krc") { name.removeLast(4) }
        if let range = name.range(of: #"_[0-9a-fA-F]{32}$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        let normalized = name.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
        let normalizedTitle = normalize(title)
        let normalizedArtist = normalize(artist)
        guard normalized.contains(normalizedTitle), !normalizedTitle.isEmpty else { return false }
        if normalizedArtist.isEmpty { return true }
        return normalized.contains(normalizedArtist)
    }

    private static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
    }

    /// 同步扫描+解码与曲目匹配的本地版本（名字初筛后通常只剩 0~3 个文件，开销可忽略）
    static func versions(title: String, artist: String) -> [Version] {
        guard let dir = cacheDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return [] }
        var result: [Version] = []
        var nameMatched = 0
        for url in entries where url.pathExtension.lowercased() == "krc" {
            guard filenameMatches(url.lastPathComponent, title: title, artist: artist) else { continue }
            nameMatched += 1
            guard let data = try? Data(contentsOf: url) else {
                DebugLog.log("本地KRC: 读取失败 \(url.lastPathComponent)")
                continue
            }
            guard let content = try? KRCDecoder.decode(data) else {
                DebugLog.log("本地KRC: 解码失败 \(url.lastPathComponent)")
                continue
            }
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            result.append(Version(
                url: url,
                title: content.title ?? title,
                artist: content.artist ?? artist,
                durationMS: content.durationMS,
                modifiedAt: modifiedAt
            ))
        }
        DebugLog.log("本地KRC: 名字命中 \(nameMatched) 个，解码成功 \(result.count) 个")
        return result
    }

    /// 多版本挑选（纯函数便于单测）：时长元数据就近；缺失或平手取修改时间新者
    /// （最近一次播放绑定的那份）。duration <= 0 表示播放时长未知，直接取最新。
    static func pick(_ versions: [Version], duration: Double) -> Version? {
        guard !versions.isEmpty else { return nil }
        if duration <= 0 {
            return versions.max { $0.modifiedAt < $1.modifiedAt }
        }
        let target = duration * 1000
        return versions.min { a, b in
            let da = a.durationMS.map { abs(Double($0) - target) } ?? .infinity
            let db = b.durationMS.map { abs(Double($0) - target) } ?? .infinity
            if da != db { return da < db }
            return a.modifiedAt > b.modifiedAt
        }
    }

    /// 主入口：为当前曲目找本地最佳版本并解码出歌词行
    static func bestMatch(for track: TrackState) -> (lines: [LyricLine], file: URL)? {
        let candidates = versions(title: track.title, artist: track.artist)
        guard let best = pick(candidates, duration: track.duration),
              let data = try? Data(contentsOf: best.url),
              let content = try? KRCDecoder.decode(data),
              !content.lines.isEmpty
        else { return nil }
        return (content.lines, best.url)
    }
}
