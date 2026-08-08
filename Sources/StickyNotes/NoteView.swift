import SwiftUI

// MARK: - 磨砂玻璃背景 (NSVisualEffectView 桥接)

struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct NoteView: View {
    @ObservedObject var note: Note
    var onClose: () -> Void
    var onModeChange: (NoteMode) -> Void
    var onNewNote: (NoteKind) -> Void
    var onToggleCollapse: () -> Void

    @State private var hovering = false
    @State private var eraseAllToken = 0

    private var highlighterMode: Bool { note.highlighterMode }

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    /// 吸附屏幕边缘时, 贴边的一侧变直角 (被屏幕"切平"的效果)
    private var cornerRadii: RectangleCornerRadii {
        let r: CGFloat = 14
        guard note.isCollapsed else {
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
        switch note.snappedEdge {
        case .left:
            return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        case .right:
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case nil:
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !note.isCollapsed {
                content
            }
        }
        .background {
            // 玻璃拟态: 磨砂玻璃透出桌面 + 半透明色彩罩保证文字可读
            ZStack {
                FrostedGlass()
                Color(nsColor: note.theme.background).opacity(0.82)
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous))
        .overlay {
            // 玻璃边缘: 上亮下暗的渐变细线
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08),
                                 .black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .animation(.spring(duration: 0.25), value: note.snappedEdge)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.18)) { hovering = h }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
            if !note.isCollapsed {
            // 关闭(删除)按钮
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .buttonStyle(.plain)
            .help("删除这张便签")

            // 新建按钮 (弹出类型选择)
            Menu {
                Button("📝 文字便签") { onNewNote(.text) }
                Button("✅ 待办事项") { onNewNote(.todo) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 19)
            .help("新建便签")
            }

            if note.isCollapsed {
                // 折叠态: 只显示标题 (删除/新建按钮隐藏, 展开后恢复)
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()   // 强制完整显示, 永不省略成 "..."
                    .padding(.leading, 2)
            }

            Spacer()

            if !note.isCollapsed && hovering {
                // 颜色切换
                ForEach(NoteTheme.allCases, id: \.self) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { note.theme = theme }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: theme.bar))
                            .frame(width: 11, height: 11)
                            .overlay {
                                Circle().strokeBorder(
                                    Color(nsColor: theme.accent)
                                        .opacity(note.theme == theme ? 0.9 : 0.25),
                                    lineWidth: note.theme == theme ? 1.5 : 1)
                            }
                            .scaleEffect(note.theme == theme ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .help(theme.displayName)
                }

                Divider().frame(height: 11).opacity(0.4)

                // 窗口模式切换
                Menu {
                    ForEach(NoteMode.allCases, id: \.self) { mode in
                        Button {
                            onModeChange(mode)
                        } label: {
                            if note.mode == mode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Text(mode.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: note.mode.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("窗口模式: \(note.mode.displayName)")
            }

            // 荧光笔 (文字和待办都有; 预览是只读视图, 不涂)
            if !note.isCollapsed && !note.isPreview {
                // 清空全部: 模式开着且真有高亮时才浮出来
                if highlighterMode && !note.highlights.isEmpty {
                    Button {
                        // 文字便签整篇由一个 NSTextView 接管, 走它才能进撤销栈;
                        // 待办是每条一个视图, 顶栏这里直接清整张。
                        if note.kind == .text {
                            eraseAllToken += 1
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) { note.highlights = [] }
                        }
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.5))
                            .frame(width: 17, height: 17)
                    }
                    .buttonStyle(.plain)
                    .help("清空这张便签的全部高亮")
                    .transition(.opacity.combined(with: .scale))
                }

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { note.highlighterMode.toggle() }
                } label: {
                    Image(systemName: "highlighter")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(highlighterMode ? accent : ink.opacity(hovering ? 0.55 : 0.22))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(accent.opacity(highlighterMode ? 0.16 : 0)))
                }
                .buttonStyle(.plain)
                .help(highlighterMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H): 拖动涂抹, 退格擦除")
            }

            // 编辑/预览切换 (折叠时隐藏)
            if !note.isCollapsed {
                Button {
                    note.highlighterMode = false
                    withAnimation(.easeInOut(duration: 0.2)) { note.isPreview.toggle() }
                } label: {
                    Image(systemName: note.isPreview ? "pencil" : "eye")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                        .frame(width: 17, height: 17)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(note.isPreview ? "回到编辑" : "预览 (只读干净视图)")
            }

            // 折叠/展开
            Button {
                note.highlighterMode = false
                onToggleCollapse()
            } label: {
                Image(systemName: note.isCollapsed
                    ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            .help(note.isCollapsed ? "展开便签" : "折叠成一行标题")
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background {
            Color(nsColor: note.theme.bar).opacity(0.5)
        }
        .overlay(alignment: .bottom) {
            // 顶栏与正文之间的发丝线
            Rectangle().fill(ink.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        if note.kind == .todo {
            TodoListView(note: note, readOnly: note.isPreview, highlighterMode: highlighterMode)
        } else if note.isPreview {
            ScrollView {
                MarkdownText(source: note.text, highlights: note.highlights,
                             bolds: note.bolds, theme: note.theme,
                             onToggleTask: { note.toggleTaskLine($0) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            HighlightedTextEditor(
                text: $note.text,
                highlights: $note.highlights,
                bolds: $note.bolds,
                theme: note.theme,
                highlighterMode: $note.highlighterMode,
                eraseAllToken: eraseAllToken)
        }
    }
}

/// 荧光笔笔头光标, 热点落在左下角的笔尖上
func highlighterCursor(_ color: NSColor) -> NSCursor {
    guard let symbol = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "荧光笔"),
          let image = symbol.withSymbolConfiguration(
            .init(pointSize: 17, weight: .regular)
            .applying(.init(paletteColors: [color.withAlphaComponent(1)])))
    else { return .crosshair }
    image.isTemplate = false
    return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: image.size.height - 2))
}

// MARK: - 带荧光笔的原生文字编辑器

/// TextEditor 无法定制原生右键菜单，也不能持久显示局部背景色，
/// 因此这里用 NSTextView 保留纯文本数据，并通过 temporary attributes 绘制高亮。
struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var highlights: [TextHighlight]
    @Binding var bolds: [TextHighlight]
    let theme: NoteTheme
    @Binding var highlighterMode: Bool
    let eraseAllToken: Int   // 顶栏「清空全部」按钮的信号, 值变了就执行一次

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = HighlighterTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = theme.text
        textView.insertionPointColor = theme.accent
        textView.string = text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: theme.text,
            .paragraphStyle: paragraph
        ]

        // 文字一变就要平移高亮, 所以立刻挂上; 等到 textDidBeginEditing 再挂会漏掉
        // MCP、历史恢复这类用户从没敲过字的便签。
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.lastSyncedText = text

        let c = context.coordinator
        textView.onPaint = { [weak c] in c?.paint($0) }
        textView.onErase = { [weak c] in c?.erase($0) }
        textView.onEraseSelection = { [weak c] in c?.eraseSelection($0) }
        textView.onEraseAll = { [weak c] in c?.eraseAll() }
        textView.onModeChange = { [weak c] in c?.setMode($0) }
        textView.hasHighlight = { [weak c] in c?.hasHighlight(in: $0) ?? false }
        textView.onToggleBold = { [weak c] in c?.toggleBold($0) }
        textView.isBold = { [weak c] in c?.parent.bolds.coversFully($0) ?? false }

        scrollView.documentView = textView
        context.coordinator.applyState(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? HighlighterTextView else { return }

        // 只有内容确实来自外部(MCP/历史恢复)才回灌。
        // 用户打字时 textStorage 回调会先改 highlights 触发一次刷新, 那一刻
        // note.text 还没跟上, 若在这里回灌就等于在 TextKit 处理编辑的过程中
        // 重入改写 text storage —— 编辑器会就此失去响应。
        if textView.string != text, text != context.coordinator.lastSyncedText {
            let caret = textView.selectedRange().location
            context.coordinator.syncingFromModel = true
            textView.string = text
            context.coordinator.syncingFromModel = false
            context.coordinator.lastSyncedText = text
            textView.setSelectedRange(
                NSRange(location: min(caret, (text as NSString).length), length: 0))
            context.coordinator.invalidateDrawing()
        }
        if context.coordinator.eraseToken != eraseAllToken {
            context.coordinator.eraseToken = eraseAllToken
            // 不能在 SwiftUI 的更新周期里改 @Binding, 挪到下一轮
            DispatchQueue.main.async { [weak c = context.coordinator] in c?.eraseAll() }
        }
        context.coordinator.applyState(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HighlightedTextEditor
        weak var textView: HighlighterTextView?
        var syncingFromModel = false
        var eraseToken: Int
        /// 最后一次由本视图同步出去的内容, 用来分辨「model 只是还没跟上」
        /// 和「内容真的被外部改了」
        var lastSyncedText: String?

        private var drawn: [TextHighlight] = []
        private var drawnBolds: [TextHighlight] = []
        private var drawnColor: NSColor?
        private var needsRedraw = true

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
            self.eraseToken = parent.eraseAllToken
        }

        func applyState(to textView: HighlighterTextView) {
            textView.highlightMode = parent.highlighterMode
            textView.textColor = parent.theme.text
            textView.insertionPointColor = parent.theme.accent
            textView.highlighterColor = parent.theme.highlighter
            textView.typingAttributes[.foregroundColor] = parent.theme.text
            redraw(in: textView)
        }

        func invalidateDrawing() { needsRedraw = true }

        // MARK: 文字同步

        /// 荧光笔是一个模式: 模式内只涂不改字, 这里是挡住所有文字改动的总闸门
        /// (打字、粘贴、拖放、输入法、撤销文字编辑都会经过它)。
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            !parent.highlighterMode
        }

        func textDidChange(_ notification: Notification) {
            guard !syncingFromModel, let textView else { return }
            lastSyncedText = textView.string
            parent.text = textView.string
            redraw(in: textView)
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !syncingFromModel else { return }
            let replaced = NSRange(location: editedRange.location,
                                   length: max(0, editedRange.length - delta))
            // 跟随文字变化的平移不进撤销栈: 撤销文字编辑时这里会被反向调用一次, 自然还原。
            let shifted = parent.highlights.shifting(replacing: replaced, newLength: editedRange.length)
            if shifted != parent.highlights { parent.highlights = shifted }
            let shiftedBolds = parent.bolds.shifting(replacing: replaced, newLength: editedRange.length)
            if shiftedBolds != parent.bolds { parent.bolds = shiftedBolds }
            // 此刻 layout manager 还没收到这次编辑, 在这里动 temporary attributes
            // 会打断输入处理, 编辑器从此不再响应按键。只标脏, 等 textDidChange
            // (编辑收尾后) 再重绘。
            needsRedraw = true
        }

        // MARK: 高亮增删

        func paint(_ range: NSRange) {
            guard range.length > 0, let textView else { return }
            let s = textView.string as NSString
            guard NSMaxRange(range) <= s.length else { return }
            let pieces = lineSegments(range, in: s)
            guard !pieces.isEmpty else { return }
            apply(pieces.reduce(parent.highlights) { $0.adding($1) }, "涂色")
        }

        func erase(_ target: NSRange) {
            guard target.length > 0 else { return }
            apply(parent.highlights.removing(target), "擦除高亮")
        }

        /// 跨行拖选时选区里夹着换行符, 给换行符上底色会让上一行的色块
        /// 一直铺到窗口右边缘。按换行切开, 再削掉每段两端的空白。
        private func lineSegments(_ range: NSRange, in s: NSString) -> [NSRange] {
            var out: [NSRange] = []
            var start = range.location
            for i in range.location..<NSMaxRange(range) {
                let c = s.character(at: i)
                guard c == 0x0A || c == 0x0D else { continue }
                if i > start { out.append(NSRange(location: start, length: i - start)) }
                start = i + 1
            }
            if NSMaxRange(range) > start {
                out.append(NSRange(location: start, length: NSMaxRange(range) - start))
            }
            return out.compactMap { trimmedBlanks($0, in: s) }
        }

        private func trimmedBlanks(_ r: NSRange, in s: NSString) -> NSRange? {
            var lo = r.location, hi = NSMaxRange(r)
            func blank(_ i: Int) -> Bool {
                guard let u = Unicode.Scalar(s.character(at: i)) else { return false }
                return CharacterSet.whitespaces.contains(u)
            }
            while lo < hi, blank(lo) { lo += 1 }
            while hi > lo, blank(hi - 1) { hi -= 1 }
            return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
        }

        /// 右键「擦除所选高亮」: 没有选区时擦掉光标所在的那一整段
        func eraseSelection(_ selection: NSRange) {
            if selection.length > 0 { erase(selection); return }
            if let h = parent.highlights.first(where: { NSLocationInRange(selection.location, $0.range) }) {
                erase(h.range)
            }
        }

        func eraseAll() { apply([], "清空高亮") }

        func hasHighlight(in selection: NSRange) -> Bool {
            if selection.length == 0 {
                return parent.highlights.contains { NSLocationInRange(selection.location, $0.range) }
            }
            return parent.highlights.contains { NSIntersectionRange($0.range, selection).length > 0 }
        }

        // MARK: 加粗

        func toggleBold(_ range: NSRange) {
            guard range.length > 0 else { return }
            if parent.bolds.coversFully(range) {
                applyBolds(parent.bolds.removing(range), "取消加粗")
            } else {
                applyBolds(parent.bolds.adding(range), "加粗")
            }
        }

        private func applyBolds(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.bolds
            guard old != new else { return }
            parent.bolds = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.applyBolds(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        func setMode(_ enabled: Bool) {
            parent.highlighterMode = enabled
            textView?.highlightMode = enabled
        }

        /// 高亮改动的唯一出口: 写模型 + 注册撤销 + 重绘
        private func apply(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.highlights
            guard old != new else { return }
            parent.highlights = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.apply(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        // MARK: 绘制与平移

        private func redraw(in textView: HighlighterTextView) {
            let color = parent.theme.highlighter
            guard needsRedraw || drawn != parent.highlights || drawnBolds != parent.bolds
                    || drawnColor != color,
                  let lm = textView.layoutManager else { return }
            // 输入法组字期间不动属性, 上屏后的 textDidChange 会再来一次
            if textView.hasMarkedText() { needsRedraw = true; return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for h in parent.highlights where h.length > 0 && NSMaxRange(h.range) <= full.length {
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: h.range)
            }
            if let ts = textView.textStorage {
                ts.beginEditing()
                ts.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: full)
                for b in parent.bolds where b.length > 0 && NSMaxRange(b.range) <= full.length {
                    ts.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: b.range)
                }
                ts.endEditing()
            }
            drawn = parent.highlights
            drawnBolds = parent.bolds
            drawnColor = color
            needsRedraw = false
        }

    }
}

// MARK: - 加粗快捷键 (菜单栏可改, 默认 ⌘B)

enum BoldShortcut {
    private static let keyKey = "boldShortcut.key"
    private static let modsKey = "boldShortcut.modifiers"

    static var key: String { UserDefaults.standard.string(forKey: keyKey) ?? "b" }

    static var modifiers: NSEvent.ModifierFlags {
        guard let raw = UserDefaults.standard.object(forKey: modsKey) as? UInt else {
            return [.command]
        }
        return NSEvent.ModifierFlags(rawValue: raw)
    }

    static func save(key: String, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(key, forKey: keyKey)
        UserDefaults.standard.set(modifiers.rawValue, forKey: modsKey)
    }

    static func matches(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers?.lowercased() == key
            && event.modifierFlags
                .intersection([.command, .control, .option, .shift]) == modifiers
    }

    static var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}

final class HighlighterTextView: NSTextView, NSMenuDelegate {
    var highlightMode = false {
        didSet {
            guard oldValue != highlightMode else { return }
            window?.invalidateCursorRects(for: self)
            if !highlightMode { NSCursor.iBeam.set() }
        }
    }
    var highlighterColor: NSColor = .systemYellow
    var onPaint: ((NSRange) -> Void)?
    var onErase: ((NSRange) -> Void)?
    var onEraseSelection: ((NSRange) -> Void)?
    var onEraseAll: (() -> Void)?
    var onModeChange: ((Bool) -> Void)?
    var hasHighlight: ((NSRange) -> Bool)?
    var onToggleBold: ((NSRange) -> Void)?
    var isBold: ((NSRange) -> Bool)?

    private var fullRange: NSRange { NSRange(location: 0, length: (string as NSString).length) }

    /// 既不能编辑也不能选中时让点击穿过去, 交给上层的 SwiftUI 手势
    /// (待办里已完成的那条, 点文字要能取消勾选)
    override func hitTest(_ point: NSPoint) -> NSView? {
        (!isEditable && !isSelectable) ? nil : super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if highlightMode { addCursorRect(visibleRect, cursor: highlighterCursor(highlighterColor)) }
    }

    // MARK: 模式内的鼠标与键盘

    /// NSTextView 的 mouseDown 内部会一直跟踪到松手才返回, 所以拖选的结果
    /// 在 super 返回后直接读: 有选区 = 拖过一段(涂色), 没选区 = 单击(只放光标)。
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard highlightMode else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        onPaint?(range)
        setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            setMode(!highlightMode)
            return true
        }
        // 加粗只在正常编辑态生效, 荧光笔模式不受影响
        if BoldShortcut.matches(event), !highlightMode, isEditable {
            let selection = selectedRange()
            if selection.length > 0 { onToggleBold?(selection) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if highlightMode, event.keyCode == 53 {   // Esc
            setMode(false)
            return
        }
        super.keyDown(with: event)
    }

    /// 模式内退格键不删字, 改成擦掉光标前一个字的高亮并左移一格
    override func deleteBackward(_ sender: Any?) {
        guard highlightMode else { super.deleteBackward(sender); return }
        let sel = selectedRange()
        if sel.length > 0 {
            onErase?(sel)
            return
        }
        guard sel.location > 0 else { return }
        // 按「一个字」擦, emoji 和组合字符算一个整体
        let prev = (string as NSString).rangeOfComposedCharacterSequence(at: sel.location - 1)
        onErase?(prev)
        setSelectedRange(NSRange(location: prev.location, length: 0))
    }

    private func setMode(_ on: Bool) {
        highlightMode = on
        onModeChange?(on)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) {
            menu.automaticallyInsertsWritingToolsItems = false
        }
        menu.delegate = self

        let selection = selectedRange()
        addItem("撤销", action: #selector(performUndo), to: menu,
                enabled: undoManager?.canUndo == true)
        addItem("重做", action: #selector(performRedo), to: menu,
                enabled: undoManager?.canRedo == true)
        menu.addItem(.separator())
        // 荧光笔模式是只读的, 改文字的项一律灰掉
        addItem("剪切", action: #selector(cut(_:)), to: menu,
                enabled: !highlightMode && selection.length > 0)
        addItem("拷贝", action: #selector(copy(_:)), to: menu, enabled: selection.length > 0)
        addItem("粘贴", action: #selector(paste(_:)), to: menu,
                enabled: !highlightMode
                    && NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil))
        addItem("全选", action: #selector(selectAll(_:)), to: menu, enabled: !string.isEmpty)

        let bold = addItem(
            isBold?(selection) == true ? "取消加粗" : "加粗",
            action: #selector(toggleBoldFromMenu), to: menu,
            enabled: !highlightMode && isEditable && selection.length > 0)
        bold.image = NSImage(systemSymbolName: "bold", accessibilityDescription: nil)
        bold.keyEquivalent = BoldShortcut.key
        bold.keyEquivalentModifierMask = BoldShortcut.modifiers
        menu.addItem(.separator())

        let highlighter = addItem(
            highlightMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H)",
            action: #selector(toggleHighlighter), to: menu, enabled: true)
        highlighter.state = highlightMode ? .on : .off
        highlighter.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)

        let erase = addItem("擦除所选高亮", action: #selector(eraseSelected), to: menu,
                            enabled: hasHighlight?(selection) == true)
        erase.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)

        let eraseEverything = addItem("清空全部高亮", action: #selector(eraseAll), to: menu,
                                      enabled: hasHighlight?(fullRange) == true)
        eraseEverything.image = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil)
        return menu
    }

    /// AppKit 会在文字菜单末尾自动追加“自动填充”和“服务”等项目；
    /// 这里仅保留便签真正需要的编辑与荧光笔操作。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let allowedActions = Set([
            "performUndo", "performRedo", "cut:", "copy:", "paste:", "selectAll:",
            "toggleBoldFromMenu", "toggleHighlighter", "eraseSelected", "eraseAll"
        ])
        for item in menu.items.reversed() where !item.isSeparatorItem {
            guard let action = item.action,
                  allowedActions.contains(NSStringFromSelector(action)) else {
                menu.removeItem(item)
                continue
            }
        }

        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        for index in menu.items.indices.reversed() where index > 0 {
            if menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
        }
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu,
                         enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    @objc private func performUndo() { undoManager?.undo() }
    @objc private func performRedo() { undoManager?.redo() }
    @objc private func toggleHighlighter() { setMode(!highlightMode) }
    @objc private func toggleBoldFromMenu() { onToggleBold?(selectedRange()) }
    @objc private func eraseSelected() { onEraseSelection?(selectedRange()) }
    @objc private func eraseAll() { onEraseAll?() }
}

// MARK: - 待办里的一条文字 (荧光笔模式专用)

/// 复用文字便签那套 TextKit 视图来渲染单条待办, 荧光笔因此在待办上
/// 也是逐字拖抹 + 退格擦除, 而不是整条涂。范围要在「本条局部」和
/// 「note.text 全局」之间来回换算, baseOffset 就是这条正文的起点。
///
/// 平时可编辑、荧光笔模式只读可涂、预览模式纯只读 —— 三种状态都走这里,
/// 高亮才能一直看得见 (换回 SwiftUI 的 Text/TextField 就画不出局部底色了)。
struct HighlightableLine: NSViewRepresentable {
    let text: String
    let baseOffset: Int
    @Binding var highlights: [TextHighlight]
    @Binding var bolds: [TextHighlight]
    let theme: NoteTheme
    let done: Bool
    let painting: Bool    // 荧光笔模式: 只读 + 可涂
    let editable: Bool    // 平时: 可以直接改字
    var onEdit: (String) -> Void
    var onExitMode: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> HighlighterTextView {
        let tv = HighlighterTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.allowsUndo = true
        tv.textStorage?.delegate = context.coordinator

        let c = context.coordinator
        tv.onPaint = { [weak c] in c?.paint($0) }
        tv.onErase = { [weak c] in c?.erase($0) }
        tv.onEraseSelection = { [weak c] in c?.eraseSelection($0) }
        tv.onEraseAll = { [weak c] in c?.eraseAll() }
        tv.onModeChange = { [weak c] enabled in if !enabled { c?.parent.onExitMode() } }
        tv.hasHighlight = { [weak c] in c?.hasHighlight(in: $0) ?? false }
        tv.onToggleBold = { [weak c] in c?.toggleBold($0) }
        tv.isBold = { [weak c] in c?.isBoldSelection($0) ?? false }

        context.coordinator.textView = tv
        context.coordinator.render(tv)
        return tv
    }

    func updateNSView(_ tv: HighlighterTextView, context: Context) {
        context.coordinator.parent = self
        tv.highlighterColor = theme.highlighter
        context.coordinator.render(tv)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HighlighterTextView,
                      context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let lm = nsView.layoutManager else { return nil }
        let width = proposal.width ?? 200
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: container)
        return CGSize(width: width, height: max(18, ceil(lm.usedRect(for: container).height)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HighlightableLine
        weak var textView: HighlighterTextView?
        private var syncing = false
        private var lastSyncedText: String?

        init(_ parent: HighlightableLine) { self.parent = parent }

        /// 荧光笔模式和预览下不许改字; 可编辑时也要挡住换行, 一条待办只能是一行
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard parent.editable, !parent.painting else { return false }
            return replacementString?.contains("\n") != true
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, let tv = textView else { return }
            lastSyncedText = tv.string
            parent.onEdit(tv.string)
        }

        /// 条内打字要把本条的高亮跟着挪, 换算成全局范围后交给共用的平移逻辑
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !syncing, parent.editable else { return }
            let replaced = NSRange(location: editedRange.location + parent.baseOffset,
                                   length: max(0, editedRange.length - delta))
            let shifted = parent.highlights.shifting(replacing: replaced, newLength: editedRange.length)
            if shifted != parent.highlights { parent.highlights = shifted }
            let shiftedBolds = parent.bolds.shifting(replacing: replaced, newLength: editedRange.length)
            if shiftedBolds != parent.bolds { parent.bolds = shiftedBolds }
        }

        func render(_ tv: HighlighterTextView) {
            tv.highlightMode = parent.painting
            // 已完成的那条不给编辑, 也不给选中, 好让点击穿透去取消勾选
            tv.isEditable = parent.editable && !parent.done
            tv.isSelectable = parent.painting || (parent.editable && !parent.done)
            // 同主编辑器: 只有内容真的来自外部才回灌, 否则会在 TextKit
            // 处理编辑的过程中重入改写, 把这一条的输入卡死。
            if tv.string != parent.text, parent.text != lastSyncedText {
                syncing = true
                let caret = tv.selectedRange().location
                tv.string = parent.text
                syncing = false
                lastSyncedText = parent.text
                tv.setSelectedRange(
                    NSRange(location: min(caret, (parent.text as NSString).length), length: 0))
            }
            let full = NSRange(location: 0, length: (parent.text as NSString).length)
            tv.textStorage?.setAttributes([
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: parent.theme.text.withAlphaComponent(parent.done ? 0.4 : 1),
                .strikethroughStyle: parent.done ? NSUnderlineStyle.single.rawValue : 0,
                .strikethroughColor: parent.theme.text.withAlphaComponent(0.45)
            ], range: full)
            tv.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: parent.theme.text.withAlphaComponent(parent.done ? 0.4 : 1)
            ]
            tv.insertionPointColor = parent.theme.accent

            for local in localRanges(of: parent.bolds, in: full.length) {
                tv.textStorage?.addAttribute(
                    .font, value: NSFont.boldSystemFont(ofSize: 14), range: local)
            }
            guard let lm = tv.layoutManager else { return }
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for local in localRanges(of: parent.highlights, in: full.length) {
                lm.addTemporaryAttribute(.backgroundColor,
                                         value: parent.theme.highlighter, forCharacterRange: local)
            }
        }

        func paint(_ local: NSRange) { apply(parent.highlights.adding(global(local)), "涂色") }
        func erase(_ local: NSRange) { apply(parent.highlights.removing(global(local)), "擦除高亮") }

        func eraseSelection(_ selection: NSRange) {
            if selection.length > 0 { erase(selection); return }
            let point = selection.location + parent.baseOffset
            if let h = parent.highlights.first(where: { NSLocationInRange(point, $0.range) }) {
                apply(parent.highlights.removing(h.range), "擦除高亮")
            }
        }

        /// 待办的「清空全部」清的是整张便签, 跟文字便签一致
        func eraseAll() { apply([], "清空高亮") }

        func isBoldSelection(_ local: NSRange) -> Bool { parent.bolds.coversFully(global(local)) }

        func toggleBold(_ local: NSRange) {
            guard local.length > 0 else { return }
            let g = global(local)
            if parent.bolds.coversFully(g) {
                applyBolds(parent.bolds.removing(g), "取消加粗")
            } else {
                applyBolds(parent.bolds.adding(g), "加粗")
            }
        }

        private func applyBolds(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.bolds
            guard old != new else { return }
            parent.bolds = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.applyBolds(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { render(textView) }
        }

        func hasHighlight(in selection: NSRange) -> Bool {
            let g = global(selection)
            if g.length == 0 {
                return parent.highlights.contains { NSLocationInRange(g.location, $0.range) }
            }
            return parent.highlights.covers(g)
        }

        private func apply(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.highlights
            guard old != new else { return }
            parent.highlights = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.apply(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { render(textView) }
        }

        private func global(_ r: NSRange) -> NSRange {
            NSRange(location: r.location + parent.baseOffset, length: r.length)
        }

        /// 整张便签的标记里, 落在这一条上的部分, 换算成本条的局部范围
        private func localRanges(of marks: [TextHighlight], in length: Int) -> [NSRange] {
            let line = NSRange(location: parent.baseOffset, length: length)
            return marks.compactMap {
                let overlap = NSIntersectionRange($0.range, line)
                guard overlap.length > 0 else { return nil }
                return NSRange(location: overlap.location - parent.baseOffset, length: overlap.length)
            }
        }
    }
}

// MARK: - 待办清单视图

struct TodoListView: View {
    @ObservedObject var note: Note
    var readOnly: Bool = false   // 预览模式: 隐藏添加/删除, 文字不可编辑
    var highlighterMode: Bool = false
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    /// 荧光笔模式下待办同样是只读的
    private var locked: Bool { readOnly || highlighterMode }

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(note.todoItems.enumerated()), id: \.offset) { index, item in
                    todoRow(index: index, item: item)
                }

                // 底部: 添加新待办 (预览/荧光笔模式下隐藏)
                if !locked {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(ink.opacity(0.3))
                        TextField("添加待办, 按回车确认", text: $newItemText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(ink)
                            .focused($addFieldFocused)
                            .onSubmit {
                                withAnimation(.spring(duration: 0.3)) {
                                    note.addTodo(newItemText)
                                }
                                newItemText = ""
                                addFieldFocused = true   // 连续输入
                            }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(13)
        }
    }

    @ViewBuilder
    private func todoRow(index: Int, item: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // 勾选框
            Button {
                withAnimation(.spring(duration: 0.3)) { note.toggleTodo(index) }
            } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? accent.opacity(0.85) : ink.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(highlighterMode)

            // 三种状态都走同一个视图, 高亮才能一直看得见
            if let range = note.todoContentRange(index) {
                HighlightableLine(
                    text: item.text,
                    baseOffset: range.location,
                    highlights: $note.highlights,
                    bolds: $note.bolds,
                    theme: note.theme,
                    done: item.done,
                    painting: highlighterMode,
                    editable: !locked,
                    onEdit: { note.setTodoText(index, $0) },
                    onExitMode: { note.highlighterMode = false })
                    .onTapGesture {
                        // 已完成的那条是只读的, 点击会落到这里: 点文字取消勾选
                        guard !locked, item.done else { return }
                        withAnimation(.spring(duration: 0.3)) { note.toggleTodo(index) }
                    }
                    // NSViewRepresentable 没有文字基线, firstTextBaseline 会退化成
                    // 按底边对齐导致勾选框和文字错位, 手动给出第一行基线位置
                    .alignmentGuide(.firstTextBaseline) { _ in
                        NSFont.systemFont(ofSize: 14).ascender
                    }
            } else {
                Text(item.text).font(.system(size: 14)).foregroundStyle(ink)
            }

            Spacer(minLength: 0)

            // 删除这一条 (预览/荧光笔模式下隐藏)
            if !locked {
                Button {
                    withAnimation(.spring(duration: 0.3)) { note.removeTodo(index) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ink.opacity(0.18))
                }
                .buttonStyle(.plain)
                .help("删除这一条")
            }
        }
        .padding(.vertical, 4)
    }

}

// MARK: - 简易 Markdown 渲染

/// 按行渲染: 支持 #/##/### 标题、- 列表、> 引用,
/// 行内的 **粗体** `代码` *斜体* [链接](url) 交给系统 AttributedString 解析。
struct MarkdownText: View {
    let source: String
    var highlights: [TextHighlight] = []
    var bolds: [TextHighlight] = []
    let theme: NoteTheme
    var onToggleTask: ((Int) -> Void)? = nil   // 参数是行号

    private var ink: Color { Color(nsColor: theme.text) }
    private var accent: Color { Color(nsColor: theme.accent) }

    private struct SourceLine: Identifiable {
        let index: Int
        let text: String
        let utf16Offset: Int
        var id: Int { index }
    }

    private var lines: [SourceLine] {
        let parts = source.components(separatedBy: "\n")
        var offset = 0
        return parts.enumerated().map { index, line in
            defer { offset += (line as NSString).length + (index < parts.count - 1 ? 1 : 0) }
            return SourceLine(index: index, text: line, utf16Offset: offset)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                renderLine(line.text, at: line.index, sourceOffset: line.utf16Offset)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String, at lineIndex: Int, sourceOffset: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let leadingOffset = trimmed.isEmpty ? 0 : (line as NSString).range(of: trimmed).location
        if trimmed.isEmpty {
            Text(" ").font(.system(size: 6))
        } else if trimmed.hasPrefix("### ") {
            inline(String(trimmed.dropFirst(4)), sourceOffset: sourceOffset + leadingOffset + 4)
                .font(.system(size: 15, weight: .semibold, design: .serif))
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3)), sourceOffset: sourceOffset + leadingOffset + 3)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .padding(.top, 2)
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .padding(.bottom, 2)
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { onToggleTask?(lineIndex) }
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent.opacity(0.85))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .help("取消完成")
                inline(String(trimmed.dropFirst(6)), sourceOffset: sourceOffset + leadingOffset + 6)
                    .font(.system(size: 14))
                    .strikethrough(true, color: ink.opacity(0.45))
                    .opacity(0.5)
            }
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { onToggleTask?(lineIndex) }
                } label: {
                    Image(systemName: "square")
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.35))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .help("标记完成")
                inline(String(trimmed.dropFirst(6)), sourceOffset: sourceOffset + leadingOffset + 6)
                    .font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 7) {
                Text("•").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent.opacity(0.7))
                inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                    .font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.5))
                    .frame(width: 2.5)
                inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                    .font(.system(size: 14))
                    .italic()
                    .opacity(0.7)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if trimmed == "---" || trimmed == "***" {
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
                .padding(.vertical, 3)
        } else {
            inline(line, sourceOffset: sourceOffset).font(.system(size: 14)).lineSpacing(4.5)
        }
    }

    private func inline(_ s: String, sourceOffset: Int) -> Text {
        guard var attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return Text(s).foregroundColor(ink)
        }
        paint(&attr, source: s, sourceOffset: sourceOffset)
        return Text(attr).foregroundColor(ink)
    }

    /// 渲染会吃掉 **、`、[]() 这些语法字符, 结果串是源码串的子序列。
    /// 逐字对齐求出「渲染结果下标 → 源码下标」的映射, 才能把高亮落在正确的字上;
    /// 按文字内容去搜索会在同一行出现重复词时涂错地方。
    private func paint(_ attr: inout AttributedString, source: String, sourceOffset: Int) {
        let line = NSRange(location: sourceOffset, length: (source as NSString).length)
        let hits = highlights.filter { NSIntersectionRange($0.range, line).length > 0 }
        let boldHits = bolds.filter { NSIntersectionRange($0.range, line).length > 0 }
        guard !hits.isEmpty || !boldHits.isEmpty else { return }

        let src = source as NSString
        let plain = String(attr.characters)
        let plainNS = plain as NSString
        var map: [Int] = []
        var cursor = 0
        for i in 0..<plainNS.length {
            let ch = plainNS.character(at: i)
            while cursor < src.length && src.character(at: cursor) != ch { cursor += 1 }
            guard cursor < src.length else { break }
            map.append(cursor)
            cursor += 1
        }

        let chars = attr.characters
        func resolved(_ hit: TextHighlight) -> Range<AttributedString.Index>? {
            let overlap = NSIntersectionRange(hit.range, line)
            let local = NSRange(location: overlap.location - sourceOffset, length: overlap.length)
            let inside = map.indices.filter {
                local.location <= map[$0] && map[$0] < NSMaxRange(local)
            }
            guard let first = inside.first, let last = inside.last,
                  let r = Range(NSRange(location: first, length: last - first + 1), in: plain)
            else { return nil }
            let lo = chars.index(chars.startIndex,
                                 offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = chars.index(lo, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            return lo..<hi
        }
        for hit in hits {
            guard let r = resolved(hit) else { continue }
            attr[r].backgroundColor = Color(nsColor: theme.highlighter)
        }
        for hit in boldHits {
            guard let r = resolved(hit) else { continue }
            attr[r].inlinePresentationIntent = .stronglyEmphasized
        }
    }
}
