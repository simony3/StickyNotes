import AppKit
import SwiftUI

/// 无边框但可输入、可拖动、可缩放的便签窗口
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // 待办和预览没有 NSTextView 接管按键, 荧光笔的开关键在窗口这一层兜底。
    // 文字便签编辑态由 HighlighterTextView 先处理, 轮不到这里。
    var onToggleHighlighter: (() -> Void)?
    /// 返回 true 表示这次 Esc 用来退出荧光笔了; 否则照常往下传,
    /// 免得吞掉待办输入框之类地方原本的 Esc。
    var onEscape: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            onToggleHighlighter?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, onEscape?() == true { return }
        super.keyDown(with: event)
    }
}

/// 待办便签的空白处也要有和文字便签同款的右键菜单;
/// 每条文字上的菜单由 HighlighterTextView 自己弹, 落到这里的都是空白区,
/// 没有文字目标的项照样列出来但灰掉。
final class NoteHostingView: NSHostingView<NoteView> {
    weak var note: Note?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let note, note.kind == .todo, !note.isCollapsed, !note.isPreview else {
            return super.menu(for: event)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let um = window?.undoManager
        menu.addItem(item("撤销", enabled: um?.canUndo == true) { [weak um] in um?.undo() })
        menu.addItem(item("重做", enabled: um?.canRedo == true) { [weak um] in um?.redo() })
        menu.addItem(.separator())
        menu.addItem(item("剪切", enabled: false) {})
        menu.addItem(item("拷贝", enabled: false) {})
        menu.addItem(item("粘贴", enabled: false) {})
        menu.addItem(item("全选", enabled: false) {})
        let bold = item("加粗", symbol: "bold", enabled: false) {}
        bold.keyEquivalent = BoldShortcut.key
        bold.keyEquivalentModifierMask = BoldShortcut.modifiers
        menu.addItem(bold)
        menu.addItem(.separator())
        let toggle = item(note.highlighterMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H)",
                          symbol: "highlighter") { [weak note] in
            note?.highlighterMode.toggle()
        }
        toggle.state = note.highlighterMode ? .on : .off
        menu.addItem(toggle)
        menu.addItem(item("擦除所选高亮", symbol: "eraser", enabled: false) {})
        menu.addItem(item("清空全部高亮", symbol: "eraser.fill",
                          enabled: !note.highlights.isEmpty) { [weak note] in
            note?.highlights = []
        })
        return menu
    }

    private func item(_ title: String, symbol: String? = nil, enabled: Bool = true,
                      handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.isEnabled = enabled
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let note: Note
    private let onDelete: (Note) -> Void
    private let onNewNote: (NoteKind) -> Void
    private var mouseUpMonitor: Any?

    init(note: Note, onDelete: @escaping (Note) -> Void, onNewNote: @escaping (NoteKind) -> Void) {
        self.note = note
        self.onDelete = onDelete
        self.onNewNote = onNewNote

        let window = NoteWindow(
            contentRect: note.frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 180, height: 120)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.onToggleHighlighter = { [weak note] in
            guard let note, !note.isCollapsed else { return }
            note.highlighterMode.toggle()
        }
        window.onEscape = { [weak note] in
            guard let note, note.highlighterMode else { return false }
            note.highlighterMode = false
            return true
        }

        let view = NoteView(
            note: note,
            onClose: { [weak self] in self?.confirmDelete() },
            onModeChange: { [weak self] mode in
                note.mode = mode
                self?.applyMode()
            },
            onNewNote: onNewNote,
            onToggleCollapse: { [weak self] in self?.toggleCollapse() }
        )
        let hosting = NoteHostingView(rootView: view)
        hosting.note = note
        window.contentView = hosting
        if note.isCollapsed {
            window.styleMask.remove(.resizable)
            window.minSize = NSSize(width: 120, height: NoteWindowController.barHeight)
        }
        applyMode()

        // 拖动松手时把吸附中的折叠条平滑归位
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.settleSnap()
            return event
        }
    }

    deinit {
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
    }

    static let barHeight: CGFloat = 30

    /// 折叠成一行标题 / 展开恢复原尺寸
    func toggleCollapse() {
        guard let window else { return }
        if note.isCollapsed {
            note.isCollapsed = false
            note.snappedEdge = nil
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 180, height: 120)
            // 顶边保持不动, 往下展开
            let target = CGRect(
                x: window.frame.minX,
                y: window.frame.maxY - note.expandedFrame.height,
                width: note.expandedFrame.width,
                height: note.expandedFrame.height)
            window.setFrame(target, display: true, animate: true)
            note.frame = target
        } else {
            note.expandedFrame = window.frame
            note.isCollapsed = true
            window.styleMask.remove(.resizable)
            window.minSize = NSSize(width: 120, height: NoteWindowController.barHeight)
            refreshCollapsedWidth()
        }
        NoteStore.shared.scheduleSave()
    }

    /// 内容被 MCP 等外部入口更新后，只重算折叠条宽度，不破坏折叠和吸附状态。
    func refreshCollapsedWidth(animated: Bool = true) {
        guard let window, note.isCollapsed else { return }
        // 宽度完全跟随标题，无上限，保证标题完整显示。
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleWidth = (note.title as NSString)
            .size(withAttributes: [.font: font]).width
        // 52 = 内边距 + 展开按钮 + 呼吸感。
        let width = max(120, ceil(titleWidth) + 52)
        // 右吸附时保持右边不动，其他情况保持左边不动。
        let x = note.snappedEdge == .right ? window.frame.maxX - width : window.frame.minX
        let target = CGRect(
            x: x,
            y: window.frame.maxY - NoteWindowController.barHeight,
            width: width,
            height: NoteWindowController.barHeight)
        window.setFrame(target, display: true, animate: animated)
        note.frame = target
        NoteStore.shared.scheduleSave()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 根据便签模式设置窗口层级
    func applyMode() {
        guard let window else { return }
        switch note.mode {
        case .floating:
            window.level = .floating
            window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        case .normal:
            window.level = .normal
            window.collectionBehavior = [.managed]
        case .desktop:
            // 高于桌面图标层(否则会被 Finder 桌面拦截点击)、低于所有正常窗口
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        }
    }

    private func confirmDelete() {
        // 空便签直接删, 有内容先确认
        if !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "删除这张便签?"
            alert.informativeText = "便签会归档到菜单栏的「历史便签」里, 可以随时查看或恢复。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        onDelete(note)
    }

    // 拖动/缩放后记住位置; 折叠条碰到屏幕左右边缘时吸附。
    // 拖动中只更新形状+触感反馈, 不动窗口位置(否则和手上的拖拽打架会抖),
    // 松开鼠标后再平滑动画归位贴边。
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }

        if note.isCollapsed, let screen = window.screen {
            let sf = screen.visibleFrame
            let f = window.frame
            let threshold: CGFloat = 16

            var edge: SnapEdge? = nil
            if f.minX - sf.minX <= threshold {
                edge = .left
            } else if sf.maxX - f.maxX <= threshold {
                edge = .right
            }

            if edge != note.snappedEdge {
                note.snappedEdge = edge
                if edge != nil {
                    // 触感反馈: 触控板轻"哒"一下
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.alignment, performanceTime: .default)
                }
            }

            // 只有非拖拽状态(程序移动/动画)才直接落位
            let dragging = NSEvent.pressedMouseButtons & 1 == 1
            if !dragging { settleSnap(animated: false) }
        }

        note.frame = window.frame
        NoteStore.shared.scheduleSave()
    }

    /// 松手后把吸附中的折叠条平滑归位到贴边位置
    func settleSnap(animated: Bool = true) {
        guard let window, note.isCollapsed, let edge = note.snappedEdge,
              let screen = window.screen else { return }
        let sf = screen.visibleFrame
        let f = window.frame
        let targetX = (edge == .left) ? sf.minX : sf.maxX - f.width
        guard abs(f.minX - targetX) > 0.5 else { return }

        let target = CGRect(x: targetX, y: f.minY, width: f.width, height: f.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
        note.frame = target
        NoteStore.shared.scheduleSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let f = window?.frame {
            note.frame = f
            NoteStore.shared.scheduleSave()
        }
    }
}
