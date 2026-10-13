import CZlibShim
import Foundation

/// 酷狗 KRC 动感歌词（krc1）解码与解析。
///
/// 文件结构：4 字节魔数 "krc1" + 密文；密文 = XOR(16 字节固定密钥) 后的 zlib 流，
/// 解压得到 UTF-8 文本。算法与密钥来自公开逆向（对照 KGG-Decryptor 实现并在
/// 本机缓存上实测验证）。文本形态：
///
///     [ar:张信哲][ti:爱如潮水][hash:...][total:275014][offset:0]
///     [17572,4584]<0,764,0>作<764,764,0>词<1528,764,0>：...
enum KRCDecoder {
    /// XOR 密钥 16 字节（以实际逆向结果为准，勿凭字符串记忆改写——曾因错误记忆踩坑）
    static let xorKey: [UInt8] = [
        0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47,
        0x51, 0x36, 0x31, 0x2D, 0xCE, 0xD2, 0x6E, 0x69,
    ]

    struct Content {
        let title: String?
        let artist: String?
        /// [total:] 总时长（毫秒），部分文件缺失
        let durationMS: Int?
        let lines: [LyricLine]
    }

    enum KRCError: Error {
        case badMagic
        case decompressFailed
    }

    static func decode(_ data: Data) throws -> Content {
        guard data.count > 4, String(data: data.prefix(4), encoding: .ascii) == "krc1" else {
            throw KRCError.badMagic
        }
        let cipher = data.dropFirst(4)
        var xored = Data(capacity: cipher.count)
        for (i, byte) in cipher.enumerated() {
            xored.append(byte ^ xorKey[i % xorKey.count])
        }
        guard let plain = zlibInflate(xored),
              var text = String(data: plain, encoding: .utf8)
        else {
            throw KRCError.decompressFailed
        }
        if text.hasPrefix("\u{feff}") {
            text.removeFirst()
        }
        return parse(text)
    }

    /// 标准 zlib 流解压。libz 的 uncompress 接受完整流（头 + deflate + adler32 尾）。
    /// 不用 Apple Compression/NSData：它们的 "zlib" 是私有变体，实测解不了酷狗的标准流。
    private static func zlibInflate(_ input: Data) -> Data? {
        guard input.count > 6 else { return nil }
        let source = Array(input)
        var capacity = 256 * 1024
        while capacity <= 8 * 1024 * 1024 {
            var dst = Data(count: capacity)
            var dstLen = uLongf(capacity)
            let status = source.withUnsafeBufferPointer { srcBuf in
                dst.withUnsafeMutableBytes { dstBuf in
                    uncompress(
                        dstBuf.baseAddress!.assumingMemoryBound(to: Bytef.self), &dstLen,
                        srcBuf.baseAddress!, uLong(source.count)
                    )
                }
            }
            if status == Z_OK {
                return dst.prefix(Int(dstLen))
            }
            if status != Z_BUF_ERROR {
                return nil
            }
            capacity *= 4
        }
        return nil
    }

    // MARK: - 文本解析

    /// 逐字标签 <offsetMs,durMs,flag> 及其后到下一个标签前的文本
    private static let wordRegex = try! NSRegularExpression(pattern: #"<(\d+),(\d+),\d+>([^<\[\r\n]*)"#)

    /// 歌词行标签是纯 "起始毫秒,时长毫秒" 形式（传入时方括号已剥掉）
    private static func lyricLineStart(_ tag: String) -> Int? {
        let parts = tag.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int(parts[0]), Int(parts[1]) != nil
        else { return nil }
        return start
    }

    static func parse(_ text: String) -> Content {
        var title: String?
        var artist: String?
        var durationMS: Int?
        var offsetMS = 0
        var lines: [LyricLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = String(line[line.index(after: line.startIndex)..<close])
            let rest = String(line[line.index(after: close)...])

            if let value = metadata(tag, key: "ti") { title = value }
            else if let value = metadata(tag, key: "ar") { artist = value }
            else if let value = metadata(tag, key: "total") { durationMS = Int(value) }
            else if let value = metadata(tag, key: "offset") { offsetMS = Int(value) ?? 0 }
            else if let lineStart = lyricLineStart(tag) {
                let lineTime = TimeInterval(lineStart - offsetMS) / 1000
                let words = parseWords(rest, lineStartMS: lineStart - offsetMS)
                let text = words.map { $0.text }.joined()
                guard !text.isEmpty else { continue }
                lines.append(LyricLine(time: max(lineTime, 0), text: text, words: words))
            }
        }
        return Content(title: title, artist: artist, durationMS: durationMS, lines: lines.sorted { $0.time < $1.time })
    }

    private static func metadata(_ tag: String, key: String) -> String? {
        guard tag.hasPrefix(key + ":"), !tag.contains(",") else { return nil }
        let value = String(tag.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func parseWords(_ rest: String, lineStartMS: Int) -> [LyricWord] {
        var words: [LyricWord] = []
        let matches = wordRegex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest))
        for match in matches {
            guard let offsetRange = Range(match.range(at: 1), in: rest),
                  let durRange = Range(match.range(at: 2), in: rest),
                  let textRange = Range(match.range(at: 3), in: rest),
                  let offset = Int(rest[offsetRange]),
                  let duration = Int(rest[durRange])
            else { continue }
            let text = String(rest[textRange])
            guard !text.isEmpty else { continue }
            words.append(LyricWord(
                time: TimeInterval(lineStartMS + offset) / 1000,
                duration: TimeInterval(duration) / 1000,
                text: text
            ))
        }
        if words.isEmpty, !rest.isEmpty {
            // 极少数无逐字标签的行：整行作为一个词
            words.append(LyricWord(time: TimeInterval(lineStartMS) / 1000, duration: 0, text: rest))
        }
        return words
    }
}
