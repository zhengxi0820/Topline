import Foundation

enum LRCParser {
    /// 时间标签，如 [01:23.45]，秒的小数部分允许 [.:] 两种分隔
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"^\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#
    )
    /// [offset:+500] 毫秒，正值表示歌词整体提前
    private static let offsetRegex = try! NSRegularExpression(
        pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#
    )

    static func parse(_ lrc: String) -> [LyricLine] {
        let offset = offsetMilliseconds(lrc)
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let (tags, rawText) = splitTags(line)
            let text = rawText.trimmingCharacters(in: .whitespaces)
            guard !tags.isEmpty, !text.isEmpty else { continue }
            for t in tags {
                lines.append(LyricLine(time: t - TimeInterval(offset) / 1000, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func offsetMilliseconds(_ lrc: String) -> Int {
        let range = NSRange(lrc.startIndex..., in: lrc)
        guard let match = offsetRegex.firstMatch(in: lrc, range: range),
              let ns = Range(match.range(at: 1), in: lrc),
              let value = Int(lrc[ns])
        else { return 0 }
        return value
    }

    /// 从行首剥出全部时间标签，剩余部分为歌词文本；一行多标签（[00:01.0][00:05.0]词）展开为多行
    private static func splitTags(_ line: String) -> ([TimeInterval], String) {
        var times: [TimeInterval] = []
        var rest = line
        while true {
            guard let match = tagRegex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest))
            else { break }
            guard let fullRange = Range(match.range, in: rest),
                  let minuteNS = Range(match.range(at: 1), in: rest),
                  let secondNS = Range(match.range(at: 2), in: rest),
                  let minute = Double(rest[minuteNS]),
                  let second = Double(rest[secondNS].replacingOccurrences(of: ":", with: "."))
            else { break }
            times.append(minute * 60 + second)
            rest = String(rest[fullRange.upperBound...])
        }
        return (times, rest)
    }
}

enum LyricScheduler {
    /// elapsed 时刻应显示的行下标（最后一个 time <= elapsed 的行）；开播前返回 nil。
    /// 行数通常只有几十，但保持二分，行为与数据量无关。
    static func currentIndex(in lines: [LyricLine], at elapsed: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var lo = 0, hi = lines.count - 1, answer = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= elapsed {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer >= 0 ? answer : nil
    }
}

/// KTV 填充进度计算（纯几何/时间数学，便于单测）
enum KaraokeMath {
    /// 当前已唱部分的渲染宽度。widths 与 words 一一对应（同字体的实测宽度）。
    /// words 为空（LRC 源无逐字数据）时按 lineDuration 线性填充。
    static func sungWidth(
        elapsed: TimeInterval,
        lineStart: TimeInterval,
        words: [LyricWord],
        widths: [CGFloat],
        totalWidth: CGFloat,
        lineDuration: TimeInterval
    ) -> CGFloat {
        guard !words.isEmpty, words.count == widths.count else {
            guard lineDuration > 0 else { return totalWidth }
            let progress = min(max((elapsed - lineStart) / lineDuration, 0), 1)
            return totalWidth * progress
        }
        var accumulated: CGFloat = 0
        for (index, word) in words.enumerated() {
            if elapsed >= word.time + word.duration {
                accumulated += widths[index]
            } else if elapsed > word.time {
                let progress = (elapsed - word.time) / max(word.duration, 0.001)
                return accumulated + widths[index] * min(max(progress, 0), 1)
            } else {
                return accumulated
            }
        }
        return accumulated
    }
}
