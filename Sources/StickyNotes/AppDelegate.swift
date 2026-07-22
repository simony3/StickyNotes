import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controllers: [UUID: NoteWindowController] = [:]
    private var historyWindow: NSWindow?

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

        if CommandLine.arguments.contains("--show-history") {
            showHistory()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveNow()
    }

    /// 在启动台/访达里再次点开 app 时:
    /// 没有便签 → 创建一张新的; 已有便签 → 全部带到前面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // 通过 URL 创建便签时 open 也会触发 reopen, 跳过避免弹类型选择框
        if Date().timeIntervalSince(lastURLHandled) < 2 { return true }
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
        menu.addItem(withTitle: "历史便签", action: #selector(showHistory), keyEquivalent: "h")
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

    @discardableResult
    private func createNote(kind: NoteKind, text: String = "", theme: NoteTheme? = nil,
                            mode: NoteMode = .floating, preview: Bool = false,
                            collapsed: Bool = false) -> Note {
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: screen.midX - 140 + cascade,
            y: screen.midY - 20 - cascade,
            width: 280, height: 280)

        // 未指定颜色时顺延取色, 避免全是黄色
        let usedThemes = NoteStore.shared.notes.map(\.theme)
        let nextTheme = theme
            ?? NoteTheme.allCases.first { !usedThemes.contains($0) }
            ?? NoteTheme.allCases[NoteStore.shared.notes.count % NoteTheme.allCases.count]

        let note = Note(text: text, kind: kind, theme: nextTheme,
                        mode: mode, isPreview: preview, frame: frame)
        NoteStore.shared.add(note)
        showWindow(note)
        if collapsed {
            controllers[note.id]?.toggleCollapse()
        }
        return note
    }

    // MARK: URL Scheme (stickynotes://add?...)
    // 供命令行 / AI 工具以细粒度命令操作便签。
    // 数据始终由正在运行的 App 通过 NoteStore 修改和保存，
    // 避免外部工具直接重写 notes.json 造成竞争或数据丢失。
    //
    // 创建:
    //   open "stickynotes://add?kind=todo&theme=mint&text=%E5%86%85%E5%AE%B9"
    // 参数: kind=text|todo, theme=lemon|peach|mint|sky|lilac,
    //       mode=floating|normal|desktop, preview=1, collapsed=1, text=百分号编码内容
    // 更新: stickynotes://update?id=<UUID>&text=...&theme=...&mode=...&preview=0|1&collapsed=0|1
    // 删除: stickynotes://delete?id=<UUID>
    // 恢复: stickynotes://restore?id=<历史记录 UUID>
    // 删除历史: stickynotes://history-delete?id=<历史记录 UUID>
    // 移动/缩放: stickynotes://frame?id=<UUID>&x=...&y=...&w=...&h=...

    private var lastURLHandled = Date.distantPast

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "stickynotes",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        lastURLHandled = Date()

        var q: [String: String] = [:]
        comps.queryItems?.forEach { q[$0.name] = $0.value }

        switch url.host {
        case "add":
            createNote(
                kind: NoteKind(rawValue: q["kind"] ?? "") ?? .text,
                text: q["text"] ?? "",
                theme: NoteTheme(rawValue: q["theme"] ?? ""),
                mode: NoteMode(rawValue: q["mode"] ?? "") ?? .floating,
                preview: q["preview"] == "1",
                collapsed: q["collapsed"] == "1")

        case "update":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            if let text = q["text"] { note.text = text }
            if let theme = NoteTheme(rawValue: q["theme"] ?? "") { note.theme = theme }
            if let mode = NoteMode(rawValue: q["mode"] ?? "") {
                note.mode = mode
                controllers[id]?.applyMode()
            }
            if note.kind == .text, let preview = queryBool(q["preview"]) {
                note.isPreview = preview
            }
            if let collapsed = queryBool(q["collapsed"]), collapsed != note.isCollapsed {
                controllers[id]?.toggleCollapse()
            } else if note.isCollapsed, q["text"] != nil {
                // 折叠条宽度跟随新标题重算，不需要先展开再折叠。
                controllers[id]?.refreshCollapsedWidth()
            }

        case "delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            delete(note)

        case "restore":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let item = NoteStore.shared.archived.first(where: { $0.id == id }) else { return }
            restore(item)

        case "history-delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr) else { return }
            NoteStore.shared.removeArchived(id)

        case "frame":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }),
                  let controller = controllers[id], let window = controller.window else { return }
            var frame = window.frame
            if let value = queryDouble(q["x"]) { frame.origin.x = value }
            if let value = queryDouble(q["y"]) { frame.origin.y = value }
            if let value = queryDouble(q["w"]) { frame.size.width = max(120, value) }
            if let value = queryDouble(q["h"]) {
                frame.size.height = note.isCollapsed ? NoteWindowController.barHeight : max(120, value)
            }
            window.setFrame(frame, display: true, animate: true)
            note.frame = frame
            if !note.isCollapsed { note.expandedFrame = frame }
            NoteStore.shared.scheduleSave()

        case "show-all":
            showAll()

        case "show-history":
            showHistory()

        default:
            break
        }
    }

    private func queryBool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes":  return true
        case "0", "false", "no": return false
        default:                    return nil
        }
    }

    private func queryDouble(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value), number.isFinite else { return nil }
        return CGFloat(number)
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
        NoteStore.shared.archive(note)   // 有内容的便签先归档进历史
        NoteStore.shared.remove(note)
    }

    // MARK: 历史便签

    @objc private func showHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if historyWindow == nil {
            let view = HistoryView(store: NoteStore.shared) { [weak self] item in
                self?.restore(item)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "历史便签"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            historyWindow = win
        }
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    /// 把历史记录恢复成一张新便签
    private func restore(_ item: ArchivedNote) {
        guard let archived = NoteStore.shared.unarchive(item.id) else { return }
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: archived.text, kind: archived.kind, theme: archived.theme,
            frame: CGRect(x: screen.midX - 140 + cascade, y: screen.midY - 20 - cascade,
                          width: 280, height: 280))
        NoteStore.shared.add(note)
        showWindow(note)
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
