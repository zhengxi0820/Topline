import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let monitor = NowPlayingMonitor()
    private let provider = LyricsProvider()
    private var lyricWindow: LyricWindow?
    private var renderTimer: Timer?
    private var versionsWindow: VersionsWindowController?
    private var styleWindow: StyleWindowController?

    private var track: TrackState?
    private var lines: [LyricLine]?
    /// 请求过歌词的曲目，失败也记录，避免同曲反复请求
    private var requestedKeys: Set<String> = []
    /// 调试日志：当前显示到的行下标
    private var lastRenderedIndex: Int?

    // 动态菜单项引用（menuNeedsUpdate 刷新标题与可用态）
    private var earlierItem: NSMenuItem?
    private var laterItem: NSMenuItem?
    private var resetOffsetItem: NSMenuItem?
    private var versionsItem: NSMenuItem?
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("启动: script=\(ResourceLocator.adapterScript ?? "nil") framework=\(ResourceLocator.adapterFramework ?? "nil")")
        let window = LyricWindow()
        // 右键歌词条 = 主菜单（菜单栏图标可能被挤掉，这里才是保底入口）
        window.menuProvider = { [weak self] in self?.statusMenu ?? NSMenu() }
        window.orderFrontRegardless()
        lyricWindow = window

        setupStatusBar()

        monitor.handler = { [weak self] state in
            self?.handleTrackState(state)
        }
        monitor.start()

        // 30Hz：KTV 逐字填充的遮罩推进；行文本只在变化时重建，开销可忽略
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer

        window.showStatus("等待播放…")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        renderTimer?.invalidate()
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "词"

        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(title: "隐藏歌词条", action: #selector(toggleWindow(_:)), keyEquivalent: "h")
        toggle.target = self
        menu.addItem(toggle)

        let lock = NSMenuItem(title: "锁定位置（点击穿透）", action: #selector(toggleLock(_:)), keyEquivalent: "l")
        lock.target = self
        menu.addItem(lock)

        let bottom = NSMenuItem(title: "回到屏幕底部", action: #selector(moveToBottom(_:)), keyEquivalent: "b")
        bottom.target = self
        menu.addItem(bottom)

        menu.addItem(NSMenuItem.separator())

        let earlier = NSMenuItem(title: "歌词提前 0.2s", action: #selector(nudgeEarlier(_:)), keyEquivalent: "")
        earlier.target = self
        menu.addItem(earlier)
        earlierItem = earlier

        let later = NSMenuItem(title: "歌词延后 0.2s", action: #selector(nudgeLater(_:)), keyEquivalent: "")
        later.target = self
        menu.addItem(later)
        laterItem = later

        let resetOffset = NSMenuItem(title: "重置本曲微调", action: #selector(resetOffset(_:)), keyEquivalent: "")
        resetOffset.target = self
        menu.addItem(resetOffset)
        resetOffsetItem = resetOffset

        menu.addItem(NSMenuItem.separator())

        let versions = NSMenuItem(title: "歌词版本…", action: #selector(openVersions(_:)), keyEquivalent: "v")
        versions.target = self
        menu.addItem(versions)
        versionsItem = versions

        let style = NSMenuItem(title: "样式…", action: #selector(openStyle(_:)), keyEquivalent: "s")
        style.target = self
        menu.addItem(style)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusMenu = menu
        statusItem = item
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let window = lyricWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
            sender.title = "显示歌词条"
        } else {
            window.orderFrontRegardless()
            sender.title = "隐藏歌词条"
        }
    }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        guard let window = lyricWindow else { return }
        let locked = !window.ignoresMouseEvents
        window.ignoresMouseEvents = locked
        sender.state = locked ? .on : .off
    }

    @objc private func moveToBottom(_ sender: NSMenuItem) {
        lyricWindow?.moveToBottom()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - 时间微调（默认 0；正值 = 歌词提前）

    @objc private func nudgeEarlier(_ sender: NSMenuItem) {
        guard let track else { return }
        let value = provider.adjustTimeOffset(by: 0.2, for: track.songKey)
        DebugLog.log(String(format: "歌词微调: 提前 -> %+.1fs", value))
    }

    @objc private func nudgeLater(_ sender: NSMenuItem) {
        guard let track else { return }
        let value = provider.adjustTimeOffset(by: -0.2, for: track.songKey)
        DebugLog.log(String(format: "歌词微调: 延后 -> %+.1fs", value))
    }

    @objc private func resetOffset(_ sender: NSMenuItem) {
        guard let track else { return }
        provider.resetTimeOffset(for: track.songKey)
        DebugLog.log("歌词微调: 已重置")
    }

    // MARK: - 版本列表窗

    @objc private func openVersions(_ sender: NSMenuItem) {
        guard let track else { return }
        if versionsWindow == nil {
            versionsWindow = VersionsWindowController()
        }
        versionsWindow?.show(
            loadVersions: { [weak self] done in
                self?.provider.versions(for: track, completion: done)
            },
            activeId: { [weak self] in
                self?.provider.activeVersionId(for: track.songKey)
            },
            onSelect: { [weak self] version in
                DebugLog.log("手动切换版本: \(version.source.rawValue) \(version.displayTitle)")
                self?.provider.applyVersion(version, for: track) { lines in
                    self?.applyLyricsResult(lines, for: track)
                }
            },
            onReset: { [weak self] in
                DebugLog.log("恢复自动匹配")
                self?.provider.clearBinding(for: track.songKey)
                self?.provider.lyrics(for: track) { [weak self] lines in
                    self?.applyLyricsResult(lines, for: track)
                }
            }
        )
    }

    // MARK: - 样式窗

    @objc private func openStyle(_ sender: NSMenuItem) {
        if styleWindow == nil {
            styleWindow = StyleWindowController { [weak self] style in
                self?.applyStyle(style)
            }
        }
        styleWindow?.show()
    }

    private func applyStyle(_ style: LyricStyle) {
        guard let window = lyricWindow else { return }
        // 条宽（含自适应展开）由窗口自身处理：style didSet 会重算最长行并调整
        window.style = style
    }

    // MARK: - 播放状态流转

    private func handleTrackState(_ state: TrackState?) {
        guard let state else {
            track = nil
            lines = nil
            lastRenderedIndex = nil
            lyricWindow?.lyricsDidChange(nil)
            lyricWindow?.showStatus("等待播放…")
            return
        }

        if track?.songKey != state.songKey {
            track = state
            lines = nil
            lastRenderedIndex = nil
            DebugLog.log("切歌: \(state.title) — \(state.artist) (\(Int(state.duration))s)")
            lyricWindow?.showStatus("正在搜索歌词…")
            if !requestedKeys.contains(state.songKey) {
                requestedKeys.insert(state.songKey)
                provider.lyrics(for: state) { [weak self] fetched in
                    self?.applyLyricsResult(fetched, for: state)
                }
            } else if provider.cachedAutoLines(for: state.songKey) == nil,
                      !provider.isFetching(state.songKey),
                      provider.binding(for: state.songKey) == nil {
                // 该曲此前已请求失败，直接提示，避免状态文案停在"搜索中"
                lyricWindow?.showStatus("未找到歌词 · \(state.title) — \(state.artist)")
            }
        } else {
            // 同一曲：刷新进度快照（拖动进度条/暂停恢复都会体现在这里）
            track = state
        }
    }

    /// 歌词结果的统一落点：换曲后的回调、版本切换、恢复自动匹配共用
    private func applyLyricsResult(_ fetched: [LyricLine]?, for state: TrackState) {
        guard track?.songKey == state.songKey else { return }
        if let fetched {
            lines = fetched
            lastRenderedIndex = nil
            lyricWindow?.lyricsDidChange(fetched)
            DebugLog.log("歌词就绪: \(fetched.count) 行")
        } else {
            lyricWindow?.lyricsDidChange(nil)
            lyricWindow?.showStatus("未找到歌词 · \(state.title) — \(state.artist)")
        }
    }

    // MARK: - 渲染

    private func render() {
        guard let track, let window = lyricWindow else { return }

        guard let lines else {
            // 歌词还没回来，状态文案由 handleTrackState 维护
            return
        }

        let elapsed = track.currentElapsed() + provider.timeOffset(for: track.songKey)
        guard let index = LyricScheduler.currentIndex(in: lines, at: elapsed) else {
            window.showStatus("♪ \(track.title) — \(track.artist)")
            return
        }
        if index != lastRenderedIndex {
            lastRenderedIndex = index
            DebugLog.log(String(format: "行进: %.1fs -> %@", elapsed, lines[index].text))
        }
        let line = lines[index]
        let nextText = index + 1 < lines.count ? lines[index + 1].text : ""
        // 行时长：到下一行开始；最后一行用曲目剩余时长（至少 5s）兜底
        let lineEnd = index + 1 < lines.count ? lines[index + 1].time : max(track.duration, line.time + 5)
        window.updateKaraoke(
            line: line,
            lineDuration: lineEnd - line.time,
            nextText: nextText,
            elapsed: elapsed
        )
    }
}

// MARK: - 菜单动态刷新

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let hasTrack = track != nil
        earlierItem?.isEnabled = hasTrack
        laterItem?.isEnabled = hasTrack
        resetOffsetItem?.isEnabled = hasTrack
        versionsItem?.isEnabled = hasTrack
        guard let track else {
            resetOffsetItem?.title = "重置本曲微调"
            return
        }
        let offset = provider.timeOffset(for: track.songKey)
        resetOffsetItem?.title = offset == 0
            ? "重置本曲微调"
            : String(format: "重置本曲微调（当前 %+.1fs）", offset)
    }
}
