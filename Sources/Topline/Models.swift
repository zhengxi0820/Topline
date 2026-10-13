import Foundation

/// perl 适配器 `get` 子命令输出的 JSON（对应系统 MediaRemote 正在播放信息）。
/// 字段全部可选：不同播放器上报的完整度不一。
struct NowPlayingInfo: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let playing: Bool?
    let playbackRate: Double?
    /// ISO8601 UTC，如 "2026-10-12T05:55:48Z"，表示 elapsedTime 的采样时刻
    let timestamp: String?
    let bundleIdentifier: String?

    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var sampledAt: Date? {
        timestamp.flatMap(NowPlayingInfo.timestampFormatter.date(from:))
    }
}

/// 一首歌的播放状态快照。轮询间隔内通过 (elapsed, sampledAt, rate) 推算实时进度，
/// 避免悬浮窗每秒都去拉一次进度。
struct TrackState: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Double

    let isPlaying: Bool
    let rate: Double
    let elapsed: Double
    let sampledAt: Date

    func currentElapsed(at date: Date = Date()) -> Double {
        guard isPlaying, rate > 0 else { return elapsed }
        return elapsed + date.timeIntervalSince(sampledAt) * rate
    }

    /// 切歌判定键：标题/歌手/时长(秒)三者一致视为同一首
    var songKey: String { "\(title)\u{1}\(artist)\u{1}\(Int(duration.rounded()))" }

    static func from(_ info: NowPlayingInfo, fallbackDate: Date = Date()) -> TrackState? {
        guard let title = info.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return TrackState(
            title: title,
            artist: info.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            album: info.album,
            duration: max(info.duration ?? 0, 0),
            isPlaying: info.playing ?? false,
            rate: info.playbackRate ?? 1,
            elapsed: max(info.elapsedTime ?? 0, 0),
            sampledAt: info.sampledAt ?? fallbackDate
        )
    }
}

/// 歌词中的一个字/词及其时间跨度，KRC 源才有；LRC 源为 nil
struct LyricWord: Codable, Equatable {
    let time: TimeInterval
    let duration: TimeInterval
    let text: String
}

/// 一行带时间轴的歌词。words 存在时 text 是逐字文本的拼接
struct LyricLine: Codable, Equatable {
    let time: TimeInterval
    let text: String
    let words: [LyricWord]?

    init(time: TimeInterval, text: String, words: [LyricWord]? = nil) {
        self.time = time
        self.text = text
        self.words = words
    }
}
