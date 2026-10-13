import Foundation

/// 定位随包分发的 perl 适配器脚本与编译产物。
/// 两种运行形态都要支持：.app 包内（正式）与仓库 .build 下直接 swift run（开发）。
enum ResourceLocator {
    static var adapterScript: String? {
        firstExisting(candidates("bin/mediaremote-adapter.pl"))
    }

    static var adapterFramework: String? {
        firstExisting(candidates("lib/MediaRemoteAdapter.framework"))
    }

    /// rel 形如 "bin/mediaremote-adapter.pl"，按可能的资源根逐个拼接
    private static func candidates(_ rel: String) -> [String] {
        var roots = [String]()
        // .app 包：.../Topline.app/Contents/Resources
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").path)
        // 仓库开发：可执行文件位于 .build/{debug,release}/，仓库根在上两级
        roots.append(
            Bundle.main.bundleURL.deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources").path
        )
        // 兜底：当前工作目录下的 Resources（从仓库根手动启动时）
        roots.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources").path
        )
        return roots.map { $0 + "/" + rel }
    }

    private static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}
