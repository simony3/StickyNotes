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

    @State private var hovering = false

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background {
            // 玻璃拟态: 磨砂玻璃透出桌面 + 半透明色彩罩保证文字可读
            ZStack {
                FrostedGlass()
                Color(nsColor: note.theme.background).opacity(0.82)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            // 玻璃边缘: 上亮下暗的渐变细线
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08),
                                 .black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .onHover { h in
            withAnimation(.easeOut(duration: 0.18)) { hovering = h }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
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

            Spacer()

            if hovering {
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

            // 编辑/预览切换
            Button {
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
            TodoListView(note: note, readOnly: note.isPreview)
        } else if note.isPreview {
            ScrollView {
                MarkdownText(source: note.text, theme: note.theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            TextEditor(text: $note.text)
                .font(.system(size: 14))
                .lineSpacing(4.5)
                .foregroundStyle(ink)
                .scrollContentBackground(.hidden)
                .padding(EdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9))
        }
    }
}

// MARK: - 待办清单视图

struct TodoListView: View {
    @ObservedObject var note: Note
    var readOnly: Bool = false   // 预览模式: 隐藏添加/删除, 文字不可编辑
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(note.todoItems.enumerated()), id: \.offset) { index, item in
                    todoRow(index: index, item: item)
                }

                // 底部: 添加新待办 (预览模式下隐藏)
                if !readOnly {
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

            if item.done {
                // 已完成: 划掉, 点文字可以取消勾选
                Text(item.text)
                    .font(.system(size: 14))
                    .strikethrough(true, color: ink.opacity(0.45))
                    .foregroundStyle(ink.opacity(0.4))
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) { note.toggleTodo(index) }
                    }
            } else if readOnly {
                // 预览模式: 只读文字
                Text(item.text)
                    .font(.system(size: 14))
                    .foregroundStyle(ink)
            } else {
                // 未完成: 可以直接编辑
                TextField("", text: Binding(
                    get: {
                        let items = note.todoItems
                        return items.indices.contains(index) ? items[index].text : ""
                    },
                    set: { note.setTodoText(index, $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(ink)
            }

            Spacer(minLength: 0)

            // 删除这一条 (预览模式下隐藏)
            if !readOnly {
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
    let theme: NoteTheme

    private var ink: Color { Color(nsColor: theme.text) }
    private var accent: Color { Color(nsColor: theme.accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Text(" ").font(.system(size: 6))
        } else if trimmed.hasPrefix("### ") {
            inline(String(trimmed.dropFirst(4)))
                .font(.system(size: 15, weight: .semibold, design: .serif))
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3)))
                .font(.system(size: 17, weight: .bold, design: .serif))
                .padding(.top, 2)
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2)))
                .font(.system(size: 21, weight: .bold, design: .serif))
                .padding(.bottom, 2)
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accent.opacity(0.85))
                    .padding(.top, 2)
                inline(String(trimmed.dropFirst(6)))
                    .font(.system(size: 14))
                    .strikethrough(true, color: ink.opacity(0.45))
                    .opacity(0.5)
            }
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "square")
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.35))
                    .padding(.top, 2)
                inline(String(trimmed.dropFirst(6))).font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 7) {
                Text("•").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent.opacity(0.7))
                inline(String(trimmed.dropFirst(2))).font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.5))
                    .frame(width: 2.5)
                inline(String(trimmed.dropFirst(2)))
                    .font(.system(size: 14))
                    .italic()
                    .opacity(0.7)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if trimmed == "---" || trimmed == "***" {
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
                .padding(.vertical, 3)
        } else {
            inline(line).font(.system(size: 14)).lineSpacing(4.5)
        }
    }

    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr).foregroundColor(ink)
        }
        return Text(s).foregroundColor(ink)
    }
}
