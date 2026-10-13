import Testing
@testable import Topline

struct LRCParserTests {
    @Test func basicParse() {
        let lrc = """
        [ti:开始懂了]
        [ar:孙燕姿]
        [00:37.08]我竟然没有调头
        [00:39.98]最残忍那一刻
        [00:43.10]静静看你走
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.count == 3)
        #expect(lines[0] == LyricLine(time: 37.08, text: "我竟然没有调头"))
        #expect(lines[2] == LyricLine(time: 43.10, text: "静静看你走"))
    }

    @Test func multipleTagsOneLine() {
        let lines = LRCParser.parse("[00:01.00][01:02.50]重复的句子")
        #expect(lines.count == 2)
        #expect(lines[0] == LyricLine(time: 1.0, text: "重复的句子"))
        #expect(lines[1] == LyricLine(time: 62.5, text: "重复的句子"))
    }

    @Test func sorting() {
        let lines = LRCParser.parse("""
        [00:30.00]后一句
        [00:10.00]前一句
        """)
        #expect(lines.map(\.text) == ["前一句", "后一句"])
    }

    @Test func offsetShiftsEarlier() {
        // offset +500ms：时间轴整体提前 0.5 秒
        let lines = LRCParser.parse("[offset:500]\n[00:10.00]词")
        #expect(abs(lines[0].time - 9.5) < 0.001)
    }

    @Test func colonAsFractionSeparator() {
        // 少见写法 [00:01:23] 的秒位冒号分隔
        let lines = LRCParser.parse("[00:01:23]词")
        #expect(abs(lines[0].time - 1.23) < 0.001)
    }

    @Test func ignoresEmptyTextAndUnknownTags() {
        let lines = LRCParser.parse("""
        [00:10.00]
        [by:某人]
        纯文本行没有时间标签
        [00:20.00]有效行
        """)
        #expect(lines.count == 1)
        #expect(lines[0].text == "有效行")
    }

    @Test func emptyInput() {
        #expect(LRCParser.parse("").isEmpty)
    }
}
