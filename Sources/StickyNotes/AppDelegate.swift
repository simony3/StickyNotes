import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controllers: [UUID: NoteWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护: 如果已经有一份在运行, 激活它并退出自己
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.simony3.stickynotes")
        if running.count > 1 {
            running.first { $0 != NSRunningApplication.current }?
                .activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()

        NoteStore.shared.load()
        if NoteStore.shared.notes.isEmpty {
            // 第一次使用给欢迎教程, 之后弹类型选择
            if UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                promptNewNote()
            } else {
                createWelcomeNote()
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        } else {
            NoteStore.shared.notes.forEach(showWindow)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveNow()
    }

    /// 在启动台/访达里再次点开 app 时:
    /// 没有便签 → 创建一张新的; 已有便签 → 全部带到前面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if controllers.isEmpty {
            promptNewNote()
        } else {
            showAll()
        }
        return true
    }

    // MARK: 菜单栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "note.text", accessibilityDescription: "StickyNotes")

        let menu = NSMenu()
        menu.addItem(withTitle: "新建文字便签", action: #selector(newTextNote), keyEquivalent: "n")
        menu.addItem(withTitle: "新建待办事项", action: #selector(newTodoNote), keyEquivalent: "t")
        menu.addItem(withTitle: "显示所有便签", action: #selector(showAll), keyEquivalent: "")
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    // MARK: 便签管理

    @objc private func newTextNote() { createNote(kind: .text) }
    @objc private func newTodoNote() { createNote(kind: .todo) }

    /// 弹出类型选择, 再创建对应类型的便签
    private func promptNewNote() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "创建新便签"
        alert.informativeText = "选择便签类型:"
        alert.addButton(withTitle: "📝 文字便签")
        alert.addButton(withTitle: "✅ 待办事项")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  createNote(kind: .text)
        case .alertSecondButtonReturn: createNote(kind: .todo)
        default: break
        }
    }

    private func createNote(kind: NoteKind) {
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: screen.midX - 140 + cascade,
            y: screen.midY - 20 - cascade,
            width: 280, height: 280)

        // 新便签沿用最近一张的颜色顺延, 避免全是黄色
        let usedThemes = NoteStore.shared.notes.map(\.theme)
        let nextTheme = NoteTheme.allCases.first { !usedThemes.contains($0) }
            ?? NoteTheme.allCases[NoteStore.shared.notes.count % NoteTheme.allCases.count]

        let note = Note(kind: kind, theme: nextTheme, frame: frame)
        NoteStore.shared.add(note)
        showWindow(note)
    }

    @objc private func showAll() {
        NSApp.activate(ignoringOtherApps: true)
        for controller in controllers.values {
            controller.window?.orderFront(nil)
            // 贴在桌面的便签临时浮上来露个脸, 3 秒后沉回桌面
            if controller.note.mode == .desktop {
                controller.window?.level = .floating
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak controller] in
                    controller?.applyMode()
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = "\(error.localizedDescription)\n\n提示: 应用需要放在“应用程序”文件夹中才能注册开机启动。"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NoteStore.shared.saveNow()
        NSApp.terminate(nil)
    }

    private func showWindow(_ note: Note) {
        if note.frame.width < 50 {
            note.frame = CGRect(x: 200, y: 200, width: 280, height: 280)
        }
        let controller = NoteWindowController(
            note: note,
            onDelete: { [weak self] n in self?.delete(n) },
            onNewNote: { [weak self] kind in self?.createNote(kind: kind) }
        )
        controller.window?.setFrame(note.frame, display: true)
        controllers[note.id] = controller
        // 淡入出现
        controller.window?.alphaValue = 0
        controller.window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            controller.window?.animator().alphaValue = 1
        }
        if note.mode != .desktop {
            controller.window?.makeKey()
        }
    }

    private func delete(_ note: Note) {
        controllers[note.id]?.window?.orderOut(nil)
        controllers[note.id] = nil
        NoteStore.shared.remove(note)
    }

    private func createWelcomeNote() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: """
            # 欢迎使用便签 👋

            这是一张支持 **Markdown** 的便签:

            - 点右上角 👁 预览渲染效果
            - 点 ✏️ 回到编辑模式
            - 鼠标悬停顶栏可换颜色、切换窗口模式
            - [ ] 待办事项写法
            - [x] 已完成事项

            > 内容自动保存, 拖动边缘可调整大小

            菜单栏的 📝 图标可以新建便签、设置开机启动。
            """,
            theme: .lemon,
            frame: CGRect(x: screen.midX - 160, y: screen.midY - 40, width: 320, height: 360))
        NoteStore.shared.add(note)
        showWindow(note)
    }
}
