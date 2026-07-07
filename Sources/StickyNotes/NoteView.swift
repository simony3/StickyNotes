import SwiftUI

struct NoteView: View {
    @ObservedObject var note: Note
    var onClose: () -> Void
    var onModeChange: (NoteMode) -> Void
    var onNewNote: (NoteKind) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(Color(nsColor: note.theme.background))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
            // 关闭(删除)按钮
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black.opacity(hovering ? 0.55 : 0.25))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.black.opacity(hovering ? 0.1 : 0.05)))
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
                    .foregroundStyle(.black.opacity(hovering ? 0.55 : 0.25))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.black.opacity(hovering ? 0.1 : 0.05)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .help("新建便签")

            Spacer()

            if hovering {
                // 颜色切换
                ForEach(NoteTheme.allCases, id: \.self) { theme in
                    Button {
                        note.theme = theme
                    } label: {
                        Circle()
                            .fill(Color(nsColor: theme.bar))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().strokeBorder(
                                    .black.opacity(note.theme == theme ? 0.45 : 0.1),
                                    lineWidth: note.theme == theme ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(theme.displayName)
                }

                Divider().frame(height: 12)

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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("窗口模式: \(note.mode.displayName)")
            }

            // 编辑/预览切换
            Button {
                note.isPreview.toggle()
            } label: {
                Image(systemName: note.isPreview ? "pencil" : "eye")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black.opacity(hovering ? 0.55 : 0.25))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(note.isPreview ? "回到编辑" : "预览 (只读干净视图)")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(nsColor: note.theme.bar))
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        if note.kind == .todo {
            TodoListView(note: note, readOnly: note.isPreview)
        } else if note.isPreview {
            ScrollView {
                MarkdownText(source: note.text, textColor: note.theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        } else {
            TextEditor(text: $note.text)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: note.theme.text))
                .scrollContentBackground(.hidden)
                .padding(EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5))
        }
    }
}

// MARK: - 待办清单视图

struct TodoListView: View {
    @ObservedObject var note: Note
    var readOnly: Bool = false   // 预览模式: 隐藏添加/删除, 文字不可编辑
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(note.todoItems.enumerated()), id: \.offset) { index, item in
                    todoRow(index: index, item: item)
                }

                // 底部: 添加新待办 (预览模式下隐藏)
                if !readOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.black.opacity(0.35))
                        TextField("添加待办, 按回车确认", text: $newItemText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($addFieldFocused)
                            .onSubmit {
                                note.addTodo(newItemText)
                                newItemText = ""
                                addFieldFocused = true   // 连续输入
                            }
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func todoRow(index: Int, item: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 勾选框
            Button {
                note.toggleTodo(index)
            } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? .green.opacity(0.75) : .black.opacity(0.4))
            }
            .buttonStyle(.plain)

            if item.done {
                // 已完成: 划掉, 点文字可以取消勾选
                Text(item.text)
                    .font(.system(size: 13))
                    .strikethrough(true, color: Color(nsColor: note.theme.text).opacity(0.55))
                    .foregroundStyle(Color(nsColor: note.theme.text).opacity(0.45))
                    .onTapGesture { note.toggleTodo(index) }
            } else if readOnly {
                // 预览模式: 只读文字
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: note.theme.text))
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
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: note.theme.text))
            }

            Spacer(minLength: 0)

            // 删除这一条 (预览模式下隐藏)
            if !readOnly {
                Button {
                    note.removeTodo(index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black.opacity(0.2))
                }
                .buttonStyle(.plain)
                .help("删除这一条")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 简易 Markdown 渲染

/// 按行渲染: 支持 #/##/### 标题、- 列表、> 引用,
/// 行内的 **粗体** `代码` *斜体* [链接](url) 交给系统 AttributedString 解析。
struct MarkdownText: View {
    let source: String
    let textColor: NSColor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                .font(.system(size: 14, weight: .semibold))
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3)))
                .font(.system(size: 16, weight: .bold))
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2)))
                .font(.system(size: 19, weight: .bold))
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.8))
                    .padding(.top, 2)
                inline(String(trimmed.dropFirst(6)))
                    .font(.system(size: 13))
                    .strikethrough(true, color: Color(nsColor: textColor).opacity(0.5))
                    .opacity(0.6)
            }
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "square")
                    .font(.system(size: 12))
                    .foregroundStyle(.black.opacity(0.45))
                    .padding(.top, 2)
                inline(String(trimmed.dropFirst(6))).font(.system(size: 13))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 13, weight: .bold))
                inline(String(trimmed.dropFirst(2))).font(.system(size: 13))
            }
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.black.opacity(0.25))
                    .frame(width: 3)
                inline(String(trimmed.dropFirst(2)))
                    .font(.system(size: 13))
                    .italic()
                    .opacity(0.75)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if trimmed == "---" || trimmed == "***" {
            Rectangle().fill(.black.opacity(0.15)).frame(height: 1)
        } else {
            inline(line).font(.system(size: 13))
        }
    }

    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr).foregroundColor(Color(nsColor: textColor))
        }
        return Text(s).foregroundColor(Color(nsColor: textColor))
    }
}
