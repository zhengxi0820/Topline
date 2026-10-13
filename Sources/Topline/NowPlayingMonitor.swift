import Foundation

/// 轮询系统"正在播放"。
///
/// macOS 15.4 起 MediaRemote 私有框架加了权限校验，第三方进程直接调用一律拿空；
/// 唯一稳定通道是借道 /usr/bin/perl（苹果签名的系统二进制）加载自带的适配器 dylib
/// 去调 MediaRemote（方案来自开源 mediaremote-adapter，见 THIRD_PARTY_LICENSES.md）。
final class NowPlayingMonitor {
    /// 轮询间隔。进度靠 (elapsed, sampledAt, rate) 插值，1 秒足够平滑。
    static let pollInterval: TimeInterval = 1.0
    /// 单次适配器调用的最长等待，防止 perl 进程挂死拖垮队列
    static let adapterTimeout: TimeInterval = 3.0

    private let queue = DispatchQueue(label: "topline.nowplaying")
    private var timer: Timer?
    private var polling = false

    /// 主线程回调；nil 表示当前没有可识别的播放（或适配器不可用）
    var handler: ((TrackState?) -> Void)?

    func start() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        // 上一轮还没返回就跳过本轮，避免排队堆积
        guard !polling else { return }
        polling = true
        queue.async { [weak self] in
            let state = Self.runAdapter().flatMap(Self.decode)
            DispatchQueue.main.async { [weak self] in
                self?.polling = false
                self?.handler?(state)
            }
        }
    }

    static func decode(_ data: Data) -> TrackState? {
        guard let info = try? JSONDecoder().decode(NowPlayingInfo.self, from: data) else { return nil }
        return TrackState.from(info)
    }

    /// 跑一次 perl 适配器拿 JSON；任何环节失败返回 nil
    static func runAdapter() -> Data? {
        guard let script = ResourceLocator.adapterScript,
              let framework = ResourceLocator.adapterFramework
        else {
            DebugLog.log("适配器资源缺失: script=\(ResourceLocator.adapterScript ?? "nil") framework=\(ResourceLocator.adapterFramework ?? "nil")")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, framework, "get", "--no-artwork"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(adapterTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
