import AppKit
import SwiftUI

/// 无边框但可输入、可拖动、可缩放的便签窗口
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NoteWindowController: NSWindowController, NSWindowDelegate {
    let note: Note
    private let onDelete: (Note) -> Void
    private let onNewNote: (NoteKind) -> Void

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
        window.contentView = NSHostingView(rootView: view)
        if note.isCollapsed {
            window.styleMask.remove(.resizable)
            window.minSize = NSSize(width: 180, height: NoteWindowController.barHeight)
        }
        applyMode()
    }

    static let barHeight: CGFloat = 30

    /// 折叠成一行标题 / 展开恢复原尺寸
    func toggleCollapse() {
        guard let window else { return }
        if note.isCollapsed {
            note.isCollapsed = false
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
            // 宽度完全跟随标题, 无上限, 保证标题一字不落完整显示
            let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let titleWidth = (note.title as NSString)
                .size(withAttributes: [.font: font]).width
            let width = ceil(titleWidth) + 120
            // 顶边保持不动, 往上收起
            let target = CGRect(
                x: window.frame.minX,
                y: window.frame.maxY - NoteWindowController.barHeight,
                width: width,
                height: NoteWindowController.barHeight)
            window.setFrame(target, display: true, animate: true)
            note.frame = target
        }
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

    // 拖动/缩放后记住位置
    func windowDidMove(_ notification: Notification) {
        if let f = window?.frame {
            note.frame = f
            NoteStore.shared.scheduleSave()
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let f = window?.frame {
            note.frame = f
            NoteStore.shared.scheduleSave()
        }
    }
}
