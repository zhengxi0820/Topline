import Foundation
import Testing
@testable import Topline

struct KaraokeMathTests {
    // 两个字：t=10s 起，各 2 秒，渲染宽度各 50
    let words = [
        LyricWord(time: 10, duration: 2, text: "你"),
        LyricWord(time: 12, duration: 2, text: "好"),
    ]

    @Test func beforeFirstWord() {
        let width = KaraokeMath.sungWidth(
            elapsed: 9.9, lineStart: 10, words: words, widths: [50, 50],
            totalWidth: 100, lineDuration: 4
        )
        #expect(width == 0)
    }

    @Test func midFirstWord() {
        let width = KaraokeMath.sungWidth(
            elapsed: 11, lineStart: 10, words: words, widths: [50, 50],
            totalWidth: 100, lineDuration: 4
        )
        #expect(abs(width - 25) < 0.001)
    }

    @Test func midSecondWord() {
        let width = KaraokeMath.sungWidth(
            elapsed: 13, lineStart: 10, words: words, widths: [50, 50],
            totalWidth: 100, lineDuration: 4
        )
        #expect(abs(width - 75) < 0.001)
    }

    @Test func afterAllWords() {
        let width = KaraokeMath.sungWidth(
            elapsed: 20, lineStart: 10, words: words, widths: [50, 50],
            totalWidth: 100, lineDuration: 4
        )
        #expect(abs(width - 100) < 0.001)
    }

    @Test func lrcFallbackLinearFill() {
        // LRC 源无逐字数据：按行时长线性填充
        let half = KaraokeMath.sungWidth(
            elapsed: 15, lineStart: 10, words: [], widths: [],
            totalWidth: 100, lineDuration: 10
        )
        #expect(abs(half - 50) < 0.001)

        let before = KaraokeMath.sungWidth(
            elapsed: 5, lineStart: 10, words: [], widths: [],
            totalWidth: 100, lineDuration: 10
        )
        #expect(before == 0)
    }

    @Test func lrcFallbackZeroDurationFillsAll() {
        let width = KaraokeMath.sungWidth(
            elapsed: 10, lineStart: 10, words: [], widths: [],
            totalWidth: 100, lineDuration: 0
        )
        #expect(width == 100)
    }
}
