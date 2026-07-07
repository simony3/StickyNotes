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
            onNewNote: onNewNote
        )
        window.contentView = NSHostingView(rootView: view)
        applyMode()
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
            alert.informativeText = "便签内容将被永久删除。"
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
