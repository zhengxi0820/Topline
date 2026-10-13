import Foundation

/// TOPLINE_DEBUG=1 时向 stderr 输出运行轨迹，便于联调；正常静默。
/// 走 stderr 是因为它无缓冲，重定向到文件也能实时看到。
enum DebugLog {
    static let enabled = ProcessInfo.processInfo.environment["TOPLINE_DEBUG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        if enabled {
            let line = "[Topline] \(message())\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
    }
}
