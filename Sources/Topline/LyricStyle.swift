import AppKit
import Foundation

/// 歌词条样式（grill 定案的 8 个旋钮）。全部带默认值，零配置可用；
/// 默认字体苹方。存 UserDefaults 单字典（JSON），朋友拷配置即整份迁移。
struct LyricStyle: Codable, Equatable {
    /// NSFont.fontName 形式，如 "PingFangSC-Semibold"
    var fontName: String = "PingFangSC-Semibold"
    var currentSize: CGFloat = 21
    /// 下一行字号 = 当前行字号 × ratio
    var nextSizeRatio: CGFloat = 0.67
    /// 六位十六进制 RRGGBB
    var unsungColorHex: String = "FFFFFF"
    var sungColorHex: String = "FFB340"
    /// 下一行不透明度 0~1（下一行颜色复用未唱颜色，靠透明度压暗）
    var nextOpacity: Double = 0.55
    /// 背景不透明度 0~1，0 = 纯文字无背景条
    var backgroundOpacity: Double = 0.45
    /// 歌词条最小宽度（pt），实际条宽自适应展开到整首歌最长行
    var width: CGFloat = 720

    static let defaults = LyricStyle()
    static let storageKey = "lyricStyle"

    static var current: LyricStyle {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let style = try? JSONDecoder().decode(LyricStyle.self, from: data)
            else { return defaults }
            return style
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    var currentFont: NSFont {
        font(named: fontName, size: currentSize)
            ?? font(named: "PingFangSC-Semibold", size: currentSize)
            ?? .systemFont(ofSize: currentSize, weight: .semibold)
    }

    var nextFont: NSFont {
        font(named: fontName, size: currentSize * nextSizeRatio)
            ?? font(named: "PingFangSC-Semibold", size: currentSize * nextSizeRatio)
            ?? .systemFont(ofSize: currentSize * nextSizeRatio, weight: .semibold)
    }

    private func font(named name: String, size: CGFloat) -> NSFont? {
        NSFont(name: name, size: size)
    }

    var unsungColor: NSColor { NSColor(hex: unsungColorHex) ?? .white }
    var sungColor: NSColor { NSColor(hex: sungColorHex) ?? .systemYellow }
    var nextColor: NSColor {
        unsungColor.withAlphaComponent(nextOpacity)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value: UInt64 = 0
        guard hex.count == 6,
              Scanner(string: hex).scanHexInt64(&value)
        else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xff) / 255.0,
            green: CGFloat((value >> 8) & 0xff) / 255.0,
            blue: CGFloat(value & 0xff) / 255.0,
            alpha: 1
        )
    }
}
