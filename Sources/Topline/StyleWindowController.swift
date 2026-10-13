import AppKit

/// 「样式…」设置窗：grill 定案的 8 个旋钮 + 恢复默认，改动即时生效并持久化
/// （LyricStyle.current），悬浮窗通过回调同步应用。
final class StyleWindowController: NSWindowController {
    private var style: LyricStyle
    private let onStyleChanged: (LyricStyle) -> Void

    private let fontLabel = NSTextField(labelWithString: "")
    private let sizeValue = NSTextField(labelWithString: "")
    private let ratioValue = NSTextField(labelWithString: "")
    private let nextOpacityValue = NSTextField(labelWithString: "")
    private let bgOpacityValue = NSTextField(labelWithString: "")
    private let widthValue = NSTextField(labelWithString: "")

    private var unsungWell: NSColorWell?
    private var sungWell: NSColorWell?
    private var nextWell: NSColorWell?
    private var sizeSlider: NSSlider?
    private var ratioSlider: NSSlider?
    private var nextOpacitySlider: NSSlider?
    private var bgOpacitySlider: NSSlider?
    private var widthSlider: NSSlider?

    init(onStyleChanged: @escaping (LyricStyle) -> Void) {
        self.style = LyricStyle.current
        self.onStyleChanged = onStyleChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "样式"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("不支持 XIB 初始化") }

    private func setupContent() {
        func row(_ label: String, _ control: NSView, value: NSTextField? = nil) -> NSView {
            let labelField = NSTextField(labelWithString: label)
            labelField.font = .systemFont(ofSize: 13)
            let trailing = value ?? NSView()
            let stack = NSStackView(views: [labelField, control, trailing])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            labelField.widthAnchor.constraint(equalToConstant: 92).isActive = true
            control.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
            if value == nil { control.widthAnchor.constraint(equalToConstant: 190).isActive = true }
            return stack
        }

        let fontButton = NSButton(title: "选择字体…", target: self, action: #selector(chooseFont))
        fontButton.bezelStyle = .rounded

        let size = slider(min: 12, max: 40, action: #selector(sizeChanged))
        let ratio = slider(min: 0.4, max: 1.0, action: #selector(ratioChanged))
        let unsung = colorWell(#selector(colorChanged))
        let sung = colorWell(#selector(colorChanged))
        let next = colorWell(#selector(colorChanged))
        unsungWell = unsung
        sungWell = sung
        nextWell = next
        let nextOpacity = slider(min: 0.2, max: 1.0, action: #selector(nextOpacityChanged))
        let bgOpacity = slider(min: 0.05, max: 0.95, action: #selector(bgOpacityChanged))
        let width = slider(min: 360, max: 1600, action: #selector(widthChanged))
        sizeSlider = size
        ratioSlider = ratio
        nextOpacitySlider = nextOpacity
        bgOpacitySlider = bgOpacity
        widthSlider = width

        let reset = NSButton(title: "恢复默认样式", target: self, action: #selector(resetClicked))
        reset.bezelStyle = .rounded

        let rows = NSStackView(views: [
            row("字体", fontButton, value: fontLabel),
            row("当前行字号", size, value: sizeValue),
            row("下一行字号比", ratio, value: ratioValue),
            row("未唱颜色", unsung),
            row("已唱填充色", sung),
            row("下一行颜色", next),
            row("下一行不透明", nextOpacity, value: nextOpacityValue),
            row("背景不透明度", bgOpacity, value: bgOpacityValue),
            row("歌词条宽度", width, value: widthValue),
        ])
        rows.orientation = .vertical
        rows.spacing = 10
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(rows)
        content.addSubview(reset)
        reset.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            reset.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            reset.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 14),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        window?.contentView = content
        refreshControls()
    }

    private func slider(min: Double, max: Double, action: Selector) -> NSSlider {
        let slider = NSSlider(value: 0, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        return slider
    }

    private func colorWell(_ action: Selector) -> NSColorWell {
        let well = NSColorWell()
        well.isBordered = true
        well.action = action
        well.target = self
        return well
    }

    func show() {
        style = LyricStyle.current
        refreshControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 控件事件

    @objc private func chooseFont() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.delegate = self
        manager.setSelectedFont(style.currentFont, isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let manager = sender else { return }
        let converted = manager.convert(style.currentFont)
        style.fontName = converted.fontName
        push()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        style.currentSize = CGFloat(round(sender.doubleValue))
        push()
    }

    @objc private func ratioChanged(_ sender: NSSlider) {
        style.nextSizeRatio = CGFloat((sender.doubleValue * 20).rounded() / 20)
        push()
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        switch sender {
        case unsungWell: style.unsungColorHex = Self.hex(from: sender.color)
        case sungWell: style.sungColorHex = Self.hex(from: sender.color)
        default: style.nextColorHex = Self.hex(from: sender.color)
        }
        push()
    }

    @objc private func nextOpacityChanged(_ sender: NSSlider) {
        style.nextOpacity = (sender.doubleValue * 20).rounded() / 20
        push()
    }

    @objc private func bgOpacityChanged(_ sender: NSSlider) {
        style.backgroundOpacity = (sender.doubleValue * 20).rounded() / 20
        push()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        let stepped = (sender.doubleValue / 20.0).rounded() * 20.0
        style.width = CGFloat(stepped)
        push()
    }

    @objc private func resetClicked() {
        style = .defaults
        push()
        refreshControls()
    }

    // MARK: - 同步

    private func push() {
        LyricStyle.current = style
        onStyleChanged(style)
        refreshLabels()
    }

    private func refreshControls() {
        unsungWell?.color = style.unsungColor
        sungWell?.color = style.sungColor
        nextWell?.color = NSColor(hex: style.nextColorHex) ?? .white
        sizeSlider?.doubleValue = Double(style.currentSize)
        ratioSlider?.doubleValue = Double(style.nextSizeRatio)
        nextOpacitySlider?.doubleValue = style.nextOpacity
        bgOpacitySlider?.doubleValue = style.backgroundOpacity
        widthSlider?.doubleValue = Double(style.width)
        refreshLabels()
    }

    private func refreshLabels() {
        fontLabel.stringValue = style.fontName
        sizeValue.stringValue = "\(Int(style.currentSize))"
        ratioValue.stringValue = String(format: "%.2f", style.nextSizeRatio)
        nextOpacityValue.stringValue = String(format: "%.2f", style.nextOpacity)
        bgOpacityValue.stringValue = String(format: "%.2f", style.backgroundOpacity)
        widthValue.stringValue = "\(Int(style.width))pt"
    }

    private static func hex(from color: NSColor) -> String {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        func byte(_ component: CGFloat) -> Int {
            lround(min(max(Double(component), 0.0), 1.0) * 255.0)
        }
        return String(format: "%02lX%02lX%02lX", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
