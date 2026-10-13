import Foundation
import Testing
@testable import Topline

struct KRCTests {
    /// 2026-10-12 从本机酷狗缓存实解出的《爱如潮水》KRC 明文节选（含逐字标签）
    static let realKRCText = """
    \u{feff}[id:$00000000]
    [ar:张信哲]
    [ti:爱如潮水]
    [hash:72cd96021828085cc00801dca54cc22b]
    [total:275014]
    [offset:0]
    [0,17572]<0,764,0>张<764,764,0>信<1528,764,0>哲
    [17572,4584]<0,764,0>作<764,764,0>词<1528,764,0>：<2292,764,0>李<3056,764,0>宗<3820,764,0>盛
    [90000,2000]没有逐字标签的整行
    """

    @Test func parseRealText() throws {
        let content = KRCDecoder.parse(Self.realKRCText)
        #expect(content.title == "爱如潮水")
        #expect(content.artist == "张信哲")
        #expect(content.durationMS == 275014)
        #expect(content.lines.count == 3)

        let first = try #require(content.lines.first)
        #expect(abs(first.time) < 0.001)
        #expect(first.text == "张信哲")
        #expect(first.words?.count == 3)
        #expect(first.words?[1].text == "信")
        #expect(abs((first.words?[1].time ?? 0) - 0.764) < 0.001)
        #expect(abs((first.words?[1].duration ?? 0) - 0.764) < 0.001)

        let second = content.lines[1]
        #expect(abs(second.time - 17.572) < 0.001)
        #expect(second.text == "作词：李宗盛")
    }

    @Test func parseFallbackLineWithoutWordTags() throws {
        let content = KRCDecoder.parse(Self.realKRCText)
        let third = try #require(content.lines.last)
        #expect(third.text == "没有逐字标签的整行")
        #expect(third.words?.count == 1)
        #expect(third.words?.first?.text == "没有逐字标签的整行")
    }

    @Test func offsetShiftsTimes() {
        let content = KRCDecoder.parse("[offset:1000]\n[10000,2000]<0,500,0>词")
        #expect(abs(content.lines[0].time - 9.0) < 0.001)
        #expect(abs((content.lines[0].words?.first?.time ?? 0) - 9.0) < 0.001)
    }

    @Test func decodeRoundtrip() throws {
        // 明文由 python 生成标准 zlib（参考实现产出的地面真值 hex），防止与 Swift 侧
        // 共用同一压缩 API 形成对称盲区（NSData/Compression 的 "zlib" 均为苹果私有变体，曾踩坑）。
        // 明文：[ar:测试歌手]/[ti:测试歌名]/[total:123456]/[offset:0]/一行三词逐字歌词
        let zlibHex = "789c8b4e2cb27ab6b5fbc5faa9cfd6f63cebec8ee58a2ec944883c9dd00b12c92f49ccb13234323631350372f3d3d28a534bac0c804c430303031d2320116b63a0630a641bd83dd9bbc006c482f09e2edd6b03560495dc310d0040452bfb"
        var zlibStream = Data()
        var idx = zlibHex.startIndex
        while idx < zlibHex.endIndex {
            let next = zlibHex.index(idx, offsetBy: 2)
            zlibStream.append(UInt8(zlibHex[idx..<next], radix: 16)!)
            idx = next
        }

        var cipher = Data(capacity: zlibStream.count)
        for (i, byte) in zlibStream.enumerated() {
            cipher.append(byte ^ KRCDecoder.xorKey[i % KRCDecoder.xorKey.count])
        }
        var file = Data("krc1".utf8)
        file.append(cipher)

        let content = try KRCDecoder.decode(file)
        #expect(content.title == "测试歌名")
        #expect(content.artist == "测试歌手")
        #expect(content.durationMS == 123456)
        #expect(content.lines.count == 1)
        let line = try #require(content.lines.first)
        #expect(line.text == "你好世")
        #expect(line.words?.count == 3)
        #expect(line.words?[1].text == "好")
        #expect(abs((line.words?[1].time ?? 0) - 1.5) < 0.001)
    }

    @Test func decodeRejectsBadMagic() {
        #expect(throws: KRCDecoder.KRCError.badMagic) {
            _ = try KRCDecoder.decode(Data("xxxx".utf8))
        }
    }
}

struct KugouLocalSourceTests {
    @Test func filenameMatching() {
        #expect(KugouLocalSource.filenameMatches(
            "张信哲 - 爱如潮水_72cd96021828085cc00801dca54cc22b.krc",
            title: "爱如潮水", artist: "张信哲"))
        // 标题含版本装饰词也能命中
        #expect(KugouLocalSource.filenameMatches(
            "庄东茹 - 给我无尽不眠的春天 (钢琴版)_24ff1e808c48ced01c0d0bcf701c57c6.krc",
            title: "给我无尽不眠的春天 (钢琴版)", artist: "庄东茹"))
        // 歌手不同不算命中（同名翻唱要靠文件内的时长选版，而非文件名）
        #expect(!KugouLocalSource.filenameMatches(
            "张信哲 - 爱如潮水_72cd96021828085cc00801dca54cc22b.krc",
            title: "爱如潮水", artist: "周杰伦"))
        // 纯数字文件无法按名匹配
        #expect(!KugouLocalSource.filenameMatches(
            "347288286.krc", title: "爱如潮水", artist: "张信哲"))
        // 歌手为空只匹配标题
        #expect(KugouLocalSource.filenameMatches(
            "张信哲 - 爱如潮水_72cd96021828085cc00801dca54cc22b.krc",
            title: "爱如潮水", artist: ""))
    }

    private func version(_ name: String, durationMS: Int?, older: Bool) -> KugouLocalSource.Version {
        KugouLocalSource.Version(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            title: "爱如潮水", artist: "张信哲", durationMS: durationMS,
            modifiedAt: older ? Date(timeIntervalSince1970: 100) : Date(timeIntervalSince1970: 200)
        )
    }

    @Test func pickByDurationCloseness() {
        let a = version("a", durationMS: 260_000, older: true)
        let b = version("b", durationMS: 274_000, older: true)
        #expect(KugouLocalSource.pick([a, b], duration: 274.0)?.url.lastPathComponent == "b")
    }

    @Test func pickTieBreaksByNewerMtime() {
        let a = version("old", durationMS: 274_000, older: true)
        let b = version("new", durationMS: 274_000, older: false)
        #expect(KugouLocalSource.pick([a, b], duration: 274.0)?.url.lastPathComponent == "new")
    }

    @Test func pickMissingDurationRankedLast() {
        let a = version("unknown", durationMS: nil, older: false)
        let b = version("known", durationMS: 274_000, older: true)
        #expect(KugouLocalSource.pick([a, b], duration: 274.0)?.url.lastPathComponent == "known")
    }

    @Test func pickUnknownTrackDurationTakesNewest() {
        let a = version("old", durationMS: 260_000, older: true)
        let b = version("new", durationMS: 274_000, older: false)
        #expect(KugouLocalSource.pick([a, b], duration: 0)?.url.lastPathComponent == "new")
    }

    @Test func pickEmptyReturnsNil() {
        #expect(KugouLocalSource.pick([], duration: 100) == nil)
    }
}
