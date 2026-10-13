import AppKit

/// 悬浮歌词条：无边框面板、置顶、可加入全屏 Space、可拖动（窗口服务器原生拖动）。
/// 当前行用两层 CATextLayer 叠加实现 KTV 逐字填充：
/// 底层 = 未唱色整行文本；上层 = 已唱色同文本，被一个从左向右加宽的遮罩裁剪。
final class LyricWindow: NSPanel {
    static let frameKey = "lyricWindowFrame"
    static let defaultHeight: CGFloat = 96

    var style: LyricStyle = .current {
        didSet { rebuildForStyle() }
    }

    /// 右键菜单提供者（菜单栏图标可能被系统因空间不足隐藏，歌词条右键是保底入口）
    var menuProvider: (() -> NSMenu)?

    private let backgroundView = NSView()
    private let currentBase = CATextLayer()
    private let currentFill = CATextLayer()
    private let currentMask = CAShapeLayer()
    private let nextLayer = CATextLayer()

    /// 当前展示的歌词行文本；nil 表示处于状态文案模式
    private var displayedLineText: String?
    private var displayedStatus: String?
    private var displayedNext: String?
    /// 逐字宽度缓存（与当前行的 words 对应），行文本变化时重建
    private var wordWidths: [CGFloat] = []
    private var renderedWidth: CGFloat = 0

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 200, y: 400, width: 1000, height: 600)
        let style = LyricStyle.current
        let fallback = NSRect(
            x: screenFrame.midX - style.width / 2,
            y: screenFrame.maxY - Self.defaultHeight - 64,
            width: style.width,
            height: Self.defaultHeight
        )
        let frame = UserDefaults.standard.string(forKey: Self.frameKey)
            .flatMap(Self.rect(fromString:)) ?? fallback

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        // 全屏应用之上显示的两个关键行为：加入所有 Space + 允许伴随全屏
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // statusBar 层级足以盖住全屏应用内容
        level = .statusBar

        // 拖动结束后窗口服务器会发 didMove：先钳回屏内再持久化
        // （原生拖动允许把无边框窗口甩出屏幕外，甩出去就抓不回来了——实测踩坑）
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: self, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.clampToScreen()
            UserDefaults.standard.set(Self.string(from: self.frame), forKey: Self.frameKey)
        }
        // 窗口尺寸变化时重新摆放文本层（样式改宽度/用户改窗口都会触发）
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: self, queue: .main
        ) { [weak self] _ in
            self?.positionLayers()
        }

        setupLayers()
        // 启动时也要钳：持久化的 frame 可能来自旧版本的无钳制拖动
        clampToScreen()
    }

    /// 保证歌词条至少有 120pt 宽留在屏幕可见区域内
    private func clampToScreen() {
        guard let visible = (NSScreen.screens.first { screen in
            screen.frame.intersects(frame)
        } ?? NSScreen.main)?.visibleFrame else { return }
        let minWidthOnScreen: CGFloat = 120
        var origin = frame.origin
        origin.x = min(
            max(origin.x, visible.minX - frame.width + minWidthOnScreen),
            visible.maxX - minWidthOnScreen
        )
        origin.y = min(
            max(origin.y, visible.minY - frame.height + 40),
            visible.maxY - frame.height
        )
        if origin != frame.origin {
            setFrameOrigin(origin)
        }
    }

    private func setupLayers() {
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(CGFloat(style.backgroundOpacity)).cgColor
        backgroundView.layer?.cornerRadius = 16

        for layer in [currentBase, currentFill, nextLayer] {
            layer.contentsScale = backingScaleFactor
            layer.alignmentMode = .center
        }
        currentFill.mask = currentMask
        currentMask.backgroundColor = NSColor.black.cgColor

        let root = backgroundView.layer!
        root.addSublayer(currentBase)
        root.addSublayer(currentFill)
        root.addSublayer(nextLayer)
        contentView = backgroundView
        positionLayers()
    }

    private func positionLayers() {
        let width = backgroundView.bounds.width
        let height = backgroundView.bounds.height
        guard width > 0, height > 0 else { return }
        let padding: CGFloat = 20
        let currentHeight = style.currentSize * 1.4
        let nextHeight = style.currentSize * style.nextSizeRatio * 1.4
        let currentFrame = CGRect(
            x: padding, y: height * 0.52,
            width: width - padding * 2, height: currentHeight
        )
        currentBase.frame = currentFrame
        currentFill.frame = currentFrame
        currentMask.frame = CGRect(origin: .zero, size: currentFrame.size)
        nextLayer.frame = CGRect(
            x: padding, y: height * 0.14,
            width: width - padding * 2, height: nextHeight
        )
    }

    // MARK: - 渲染入口

    /// 30Hz 调用。行文本变化才重建字符串与宽度缓存，其余仅推进遮罩宽度
    func updateKaraoke(
        line: LyricLine,
        lineDuration: TimeInterval,
        nextText: String,
        elapsed: TimeInterval
    ) {
        displayedStatus = nil

        if line.text != displayedLineText {
            displayedLineText = line.text
            let font = style.currentFont
            let base = NSAttributedString(string: line.text, attributes: [
                .font: font, .foregroundColor: style.unsungColor,
            ])
            let fill = NSAttributedString(string: line.text, attributes: [
                .font: font, .foregroundColor: style.sungColor,
            ])
            renderedWidth = ceil(base.size().width)
            wordWidths = (line.words ?? []).map { word in
                ceil(NSAttributedString(string: word.text, attributes: [.font: font]).size().width)
            }
            currentBase.string = base
            currentFill.string = fill
        }

        if nextText != displayedNext {
            displayedNext = nextText
            if nextText.isEmpty {
                nextLayer.isHidden = true
            } else {
                nextLayer.isHidden = false
                nextLayer.string = NSAttributedString(string: nextText, attributes: [
                    .font: style.nextFont, .foregroundColor: style.nextColor,
                ])
            }
        }

        let layerWidth = currentBase.bounds.width
        let sung = KaraokeMath.sungWidth(
            elapsed: elapsed, lineStart: line.time,
            words: line.words ?? [], widths: wordWidths,
            totalWidth: renderedWidth, lineDuration: lineDuration
        )
        // 文本居中渲染，遮罩宽度 = 居中偏移 + 已唱宽度
        let centerOffset = max((layerWidth - renderedWidth) / 2, 0)
        let maskWidth = min(max(centerOffset + sung, 0), layerWidth)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentMask.path = CGPath(
            rect: CGRect(x: 0, y: 0, width: maskWidth, height: currentBase.bounds.height),
            transform: nil
        )
        CATransaction.commit()
    }

    /// 单条状态文案（等待播放 / 搜索歌词中 / ♪ 歌名 — 歌手）
    func showStatus(_ text: String) {
        guard text != displayedStatus else { return }
        displayedStatus = text
        displayedLineText = nil
        displayedNext = nil
        wordWidths = []
        currentBase.string = NSAttributedString(string: text, attributes: [
            .font: style.currentFont, .foregroundColor: style.unsungColor,
        ])
        currentFill.string = nil
        currentMask.path = nil
        nextLayer.isHidden = true
    }

    // MARK: - 样式

    private func rebuildForStyle() {
        backgroundView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(CGFloat(style.backgroundOpacity)).cgColor
        if let status = displayedStatus {
            displayedStatus = nil
            showStatus(status)
        } else {
            // 置空缓存，让下一个 30Hz 帧按新样式重建两行文本
            displayedLineText = nil
            displayedNext = nil
        }
        positionLayers()
    }

    // MARK: - 拖动

    /// 交给窗口服务器原生拖动。应用侧逐事件 setFrameOrigin 会有可感知的滞后
    /// （事件进出进程 + 自动布局重算都在移动路径上），原生拖动完全没有。
    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }

    /// 右键弹出主菜单：菜单栏状态项可能因空间不足被系统隐藏，这里才是保底入口
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() {
            let location = backgroundView.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: location, in: backgroundView)
        }
    }

    // MARK: - frame 持久化

    private static func string(from rect: NSRect) -> String {
        "\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)"
    }

    private static func rect(fromString s: String) -> NSRect? {
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}
