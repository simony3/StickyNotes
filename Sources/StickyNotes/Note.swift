import AppKit
import Combine

// MARK: - 颜色主题

enum NoteTheme: String, Codable, CaseIterable {
    case lemon, peach, mint, sky, lilac

    var displayName: String {
        switch self {
        case .lemon: return "柠檬黄"
        case .peach: return "蜜桃粉"
        case .mint:  return "薄荷绿"
        case .sky:   return "天空蓝"
        case .lilac: return "丁香紫"
        }
    }

    /// 便签主体背景色 (低饱和莫兰迪色, 叠在磨砂玻璃上)
    var background: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        case .peach: return NSColor(red: 0.98, green: 0.93, blue: 0.91, alpha: 1)
        case .mint:  return NSColor(red: 0.92, green: 0.95, blue: 0.92, alpha: 1)
        case .sky:   return NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
        case .lilac: return NSColor(red: 0.95, green: 0.93, blue: 0.97, alpha: 1)
        }
    }

    /// 顶栏轻微加深的颜色
    var bar: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.93, green: 0.89, blue: 0.76, alpha: 1)
        case .peach: return NSColor(red: 0.95, green: 0.85, blue: 0.82, alpha: 1)
        case .mint:  return NSColor(red: 0.84, green: 0.90, blue: 0.85, alpha: 1)
        case .sky:   return NSColor(red: 0.83, green: 0.88, blue: 0.94, alpha: 1)
        case .lilac: return NSColor(red: 0.88, green: 0.84, blue: 0.94, alpha: 1)
        }
    }

    /// 同色系强调色 (勾选框、引用条、选中态)
    var accent: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.71, green: 0.58, blue: 0.22, alpha: 1)
        case .peach: return NSColor(red: 0.80, green: 0.47, blue: 0.40, alpha: 1)
        case .mint:  return NSColor(red: 0.36, green: 0.58, blue: 0.44, alpha: 1)
        case .sky:   return NSColor(red: 0.34, green: 0.53, blue: 0.74, alpha: 1)
        case .lilac: return NSColor(red: 0.55, green: 0.45, blue: 0.73, alpha: 1)
        }
    }

    /// 正文文字颜色 (暖墨色, 深一点保证醒目)
    var text: NSColor {
        NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1)
    }
}

// MARK: - 窗口层级模式

enum NoteMode: String, Codable, CaseIterable {
    case floating   // 置顶悬浮
    case normal     // 普通窗口
    case desktop    // 贴在桌面

    var displayName: String {
        switch self {
        case .floating: return "置顶悬浮"
        case .normal:   return "普通窗口"
        case .desktop:  return "贴在桌面"
        }
    }

    var symbol: String {
        switch self {
        case .floating: return "pin.fill"
        case .normal:   return "macwindow"
        case .desktop:  return "square.grid.3x3.bottomright.filled"
        }
    }
}

// MARK: - 便签类型

enum NoteKind: String, Codable, CaseIterable {
    case text   // 纯文字便签
    case todo   // 待办事项便签

    var displayName: String {
        switch self {
        case .text: return "文字便签"
        case .todo: return "待办事项"
        }
    }
}

// MARK: - 便签模型

final class Note: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var text: String
    @Published var theme: NoteTheme
    @Published var mode: NoteMode
    @Published var isPreview: Bool   // true = 渲染 Markdown, false = 编辑原文
    let kind: NoteKind
    var frame: CGRect

    init(id: UUID = UUID(),
         text: String = "",
         kind: NoteKind = .text,
         theme: NoteTheme = .lemon,
         mode: NoteMode = .floating,
         isPreview: Bool = false,
         frame: CGRect = .zero) {
        self.id = id
        self.text = text
        self.kind = kind
        self.theme = theme
        self.mode = mode
        self.isPreview = isPreview
        self.frame = frame
    }

    // Codable (手动实现, 因为 @Published 不能自动合成)
    enum CodingKeys: String, CodingKey {
        case id, text, kind, theme, mode, isPreview, x, y, w, h
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: try c.decode(String.self, forKey: .text),
            kind: try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text,
            theme: try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon,
            mode: try c.decodeIfPresent(NoteMode.self, forKey: .mode) ?? .floating,
            isPreview: try c.decodeIfPresent(Bool.self, forKey: .isPreview) ?? false,
            frame: CGRect(
                x: try c.decodeIfPresent(Double.self, forKey: .x) ?? 0,
                y: try c.decodeIfPresent(Double.self, forKey: .y) ?? 0,
                width: try c.decodeIfPresent(Double.self, forKey: .w) ?? 280,
                height: try c.decodeIfPresent(Double.self, forKey: .h) ?? 280
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(kind, forKey: .kind)
        try c.encode(theme, forKey: .theme)
        try c.encode(mode, forKey: .mode)
        try c.encode(isPreview, forKey: .isPreview)
        try c.encode(frame.origin.x, forKey: .x)
        try c.encode(frame.origin.y, forKey: .y)
        try c.encode(frame.width, forKey: .w)
        try c.encode(frame.height, forKey: .h)
    }
}

// MARK: - 待办事项读写
// 待办便签把条目存在 text 里, 每行一条: "[ ] 内容" 或 "[x] 内容"

struct TodoItem {
    var text: String
    var done: Bool
}

extension Note {
    var todoItems: [TodoItem] {
        text.components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            if t.hasPrefix("[x] ") || t.hasPrefix("[X] ") {
                return TodoItem(text: String(t.dropFirst(4)), done: true)
            }
            if t.hasPrefix("[ ] ") {
                return TodoItem(text: String(t.dropFirst(4)), done: false)
            }
            return TodoItem(text: t, done: false)
        }
    }

    private func writeTodos(_ items: [TodoItem]) {
        text = items
            .map { "\($0.done ? "[x]" : "[ ]") \($0.text)" }
            .joined(separator: "\n")
    }

    func toggleTodo(_ index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].done.toggle()
        writeTodos(items)
    }

    func setTodoText(_ index: Int, _ newText: String) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].text = newText
        writeTodos(items)
    }

    func addTodo(_ itemText: String) {
        let t = itemText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var items = todoItems
        items.append(TodoItem(text: t, done: false))
        writeTodos(items)
    }

    func removeTodo(_ index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        writeTodos(items)
    }
}

// MARK: - 存储

final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    private var cancellables: [UUID: AnyCancellable] = [:]
    private var saveWorkItem: DispatchWorkItem?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else {
            notes = []
            return
        }
        notes = decoded
        notes.forEach(observe)
    }

    func add(_ note: Note) {
        notes.append(note)
        observe(note)
        scheduleSave()
    }

    func remove(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        cancellables[note.id] = nil
        scheduleSave()
    }

    private func observe(_ note: Note) {
        // 内容/主题/模式变化后延迟自动保存
        cancellables[note.id] = note.objectWillChange
            .sink { [weak self] _ in self?.scheduleSave() }
    }

    /// 防抖: 停止输入 1 秒后写盘
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
