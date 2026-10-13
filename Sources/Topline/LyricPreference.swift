import Foundation

/// 一个可选歌词版本的描述：列表展示 + 绑定后跨启动重放的完整信息
struct LyricVersion: Codable, Equatable {
    enum Source: String, Codable {
        case localKRC = "本地KRC"
        case kugou = "酷狗"
        case netease = "网易云"
    }

    let source: Source
    let title: String
    let artist: String
    let durationMS: Int?
    /// 版本重放凭据：本地 = 缓存文件名；酷狗 = "id|accesskey"；网易云 = songId
    let payload: String

    var id: String { "\(source.rawValue)|\(payload)" }

    var displayTitle: String { "\(artist) — \(title)" }
    var displayDuration: String {
        guard let durationMS, durationMS > 0 else { return "—" }
        let seconds = durationMS / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 版本绑定与每曲时间偏移的持久化（UserDefaults，JSON 编码，可整体拷给朋友）
enum LyricPreference {
    static let bindingsKey = "versionBindings"
    static let offsetsKey = "lyricTimeOffsets"

    static func binding(for songKey: String, defaults: UserDefaults = .standard) -> LyricVersion? {
        loadBindings(defaults: defaults)[songKey]
    }

    static func setBinding(_ version: LyricVersion?, for songKey: String, defaults: UserDefaults = .standard) {
        var all = loadBindings(defaults: defaults)
        if let version {
            all[songKey] = version
        } else {
            all.removeValue(forKey: songKey)
        }
        saveBindings(all, defaults: defaults)
    }

    static func timeOffset(for songKey: String, defaults: UserDefaults = .standard) -> Double {
        loadOffsets(defaults: defaults)[songKey] ?? 0
    }

    /// 正值 = 歌词提前。夹在 ±5s 防误触
    static func setTimeOffset(_ offset: Double, for songKey: String, defaults: UserDefaults = .standard) {
        var all = loadOffsets(defaults: defaults)
        let clamped = min(max(offset, -5), 5)
        if clamped == 0 {
            all.removeValue(forKey: songKey)
        } else {
            all[songKey] = clamped
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: offsetsKey)
        }
    }

    private static func loadBindings(defaults: UserDefaults) -> [String: LyricVersion] {
        guard let data = defaults.data(forKey: bindingsKey),
              let all = try? JSONDecoder().decode([String: LyricVersion].self, from: data)
        else { return [:] }
        return all
    }

    private static func saveBindings(_ all: [String: LyricVersion], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: bindingsKey)
        }
    }

    private static func loadOffsets(defaults: UserDefaults) -> [String: Double] {
        guard let data = defaults.data(forKey: offsetsKey),
              let all = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return all
    }
}
