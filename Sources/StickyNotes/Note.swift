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

    /// 针对每种便签底色挑选的对比荧光色。
    /// 高亮只保存文字范围，切换主题时会自动改用这里的新颜色。
    var highlighter: NSColor {
        switch self {
        case .lemon: return NSColor(red: 1.00, green: 0.38, blue: 0.30, alpha: 0.44) // 珊瑚红
        case .peach: return NSColor(red: 1.00, green: 0.72, blue: 0.08, alpha: 0.56) // 琥珀黄
        case .mint:  return NSColor(red: 0.57, green: 0.36, blue: 1.00, alpha: 0.42) // 明亮紫
        case .sky:   return NSColor(red: 0.55, green: 0.86, blue: 0.22, alpha: 0.48) // 青柠绿
        case .lilac: return NSColor(red: 0.12, green: 0.78, blue: 0.69, alpha: 0.45) // 湖水青
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

// MARK: - 折叠条吸附边

enum SnapEdge: String, Codable {
    case left, right
}

/// 文字便签中的一段荧光标记。范围使用 UTF-16，与 NSTextView/NSRange 一致。
struct TextHighlight: Codable, Equatable {
    var location: Int
    var length: Int

    var range: NSRange { NSRange(location: location, length: length) }

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }
}

extension Array where Element == TextHighlight {
    /// 并入一段, 与已有高亮相接的自动合成一段
    func adding(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        var out: [NSRange] = []
        for r in (map(\.range) + [range]).sorted(by: { $0.location < $1.location }) where r.length > 0 {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1] = NSUnionRange(last, r)
            } else {
                out.append(r)
            }
        }
        return out.map(TextHighlight.init)
    }

    /// 挖掉一段, 被从中间穿过的高亮断成两截
    func removing(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        return flatMap { h -> [NSRange] in
            let overlap = NSIntersectionRange(h.range, range)
            guard overlap.length > 0 else { return [h.range] }
            var parts: [NSRange] = []
            if h.location < overlap.location {
                parts.append(NSRange(location: h.location, length: overlap.location - h.location))
            }
            if NSMaxRange(overlap) < NSMaxRange(h.range) {
                parts.append(NSRange(location: NSMaxRange(overlap),
                                     length: NSMaxRange(h.range) - NSMaxRange(overlap)))
            }
            return parts
        }.map(TextHighlight.init)
    }

    func covers(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    /// 整段都落在同一段标记之内 (adding 合并相邻段, 全覆盖时必在单段里)
    func coversFully(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return contains { NSLocationInRange(range.location, $0.range)
            && NSMaxRange(range) <= NSMaxRange($0.range) }
    }

    /// 文字被替换后平移。落进替换区里的部分直接丢掉,
    /// 所以全选改写会让高亮自然清空, 不需要额外判断。
    func shifting(replacing old: NSRange, newLength: Int) -> [TextHighlight] {
        let delta = newLength - old.length
        let oldEnd = NSMaxRange(old)
        return flatMap { h -> [NSRange] in
            let r = h.range, hEnd = NSMaxRange(r)
            if hEnd <= old.location { return [r] }
            if r.location >= oldEnd { return [NSRange(location: r.location + delta, length: r.length)] }
            // 在高亮内部打字: 新字一并纳进这段高亮
            if old.length == 0 { return [NSRange(location: r.location, length: r.length + delta)] }
            var parts: [NSRange] = []
            if r.location < old.location {
                parts.append(NSRange(location: r.location, length: old.location - r.location))
            }
            if hEnd > oldEnd {
                parts.append(NSRange(location: oldEnd + delta, length: hEnd - oldEnd))
            }
            return parts
        }.map(TextHighlight.init)
    }
}

// MARK: - 便签模型

final class Note: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var text: String
    @Published var theme: NoteTheme
    @Published var mode: NoteMode
    @Published var isPreview: Bool   // true = 渲染 Markdown, false = 编辑原文
    @Published var isCollapsed: Bool // true = 折叠成一行标题
    @Published var snappedEdge: SnapEdge?  // 折叠条吸附在屏幕哪条边
    @Published var highlights: [TextHighlight]
    @Published var bolds: [TextHighlight]
    /// 荧光笔模式。纯 UI 状态不进 Codable, 但要放在这里,
    /// 窗口层才能统一处理 Esc / ⌘⇧H (待办和预览没有 NSTextView 接管按键)。
    @Published var highlighterMode = false
    let kind: NoteKind
    var frame: CGRect
    var expandedFrame: CGRect        // 折叠前的尺寸, 展开时恢复

    init(id: UUID = UUID(),
         text: String = "",
         kind: NoteKind = .text,
         theme: NoteTheme = .lemon,
         mode: NoteMode = .floating,
         isPreview: Bool = false,
         isCollapsed: Bool = false,
         snappedEdge: SnapEdge? = nil,
         highlights: [TextHighlight] = [],
         bolds: [TextHighlight] = [],
         frame: CGRect = .zero,
         expandedFrame: CGRect? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.theme = theme
        self.mode = mode
        self.isPreview = isPreview
        self.isCollapsed = isCollapsed
        self.snappedEdge = snappedEdge
        self.highlights = highlights
        self.bolds = bolds
        self.frame = frame
        self.expandedFrame = expandedFrame ?? frame
    }

    /// 折叠时显示的标题: 文字便签取第一行非空内容, 去掉 Markdown 符号;
    /// 待办便签取第一个未完成任务并加进度, 全部完成时显示"全部完成"
    var title: String {
        if kind == .todo {
            let items = todoItems
            if !items.isEmpty {
                let done = items.filter(\.done).count
                let current = items.first { !$0.done }?.text ?? "全部完成"
                return "\(done)/\(items.count) · \(current)"
            }
        }
        var first = ""
        for line in text.components(separatedBy: "\n") {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            for p in ["# ", "## ", "### ", "- [x] ", "- [X] ", "- [ ] ",
                      "[x] ", "[X] ", "[ ] ", "- ", "* ", "> "] {
                if t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
            }
            if !t.isEmpty { first = t; break }
        }
        return first.isEmpty ? "空便签" : first
    }

    // Codable (手动实现, 因为 @Published 不能自动合成)
    enum CodingKeys: String, CodingKey {
        case id, text, kind, theme, mode, isPreview, isCollapsed, snap, highlights, bolds
        case x, y, w, h, ex, ey, ew, eh
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let frame = CGRect(
            x: try c.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try c.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            width: try c.decodeIfPresent(Double.self, forKey: .w) ?? 280,
            height: try c.decodeIfPresent(Double.self, forKey: .h) ?? 280
        )
        var expanded: CGRect? = nil
        if let ew = try c.decodeIfPresent(Double.self, forKey: .ew),
           let eh = try c.decodeIfPresent(Double.self, forKey: .eh) {
            expanded = CGRect(
                x: try c.decodeIfPresent(Double.self, forKey: .ex) ?? frame.origin.x,
                y: try c.decodeIfPresent(Double.self, forKey: .ey) ?? frame.origin.y,
                width: ew, height: eh)
        }
        let text = try c.decode(String.self, forKey: .text)
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: text,
            kind: try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text,
            theme: try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon,
            mode: try c.decodeIfPresent(NoteMode.self, forKey: .mode) ?? .floating,
            isPreview: try c.decodeIfPresent(Bool.self, forKey: .isPreview) ?? false,
            isCollapsed: try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false,
            snappedEdge: try c.decodeIfPresent(SnapEdge.self, forKey: .snap),
            highlights: try ranges(.highlights),
            bolds: try ranges(.bolds),
            frame: frame,
            expandedFrame: expanded
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
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encodeIfPresent(snappedEdge, forKey: .snap)
        if !highlights.isEmpty { try c.encode(highlights, forKey: .highlights) }
        if !bolds.isEmpty { try c.encode(bolds, forKey: .bolds) }
        try c.encode(frame.origin.x, forKey: .x)
        try c.encode(frame.origin.y, forKey: .y)
        try c.encode(frame.width, forKey: .w)
        try c.encode(frame.height, forKey: .h)
        try c.encode(expandedFrame.origin.x, forKey: .ex)
        try c.encode(expandedFrame.origin.y, forKey: .ey)
        try c.encode(expandedFrame.width, forKey: .ew)
        try c.encode(expandedFrame.height, forKey: .eh)
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

    /// 条目一增删改字, 后面所有条目在 text 里的位置就整体平移。
    /// 高亮按「第几条 + 条内偏移」重新落位, 否则涂过的荧光会飘到别的字上。
    private func rebuildText(_ items: [TodoItem]) {
        text = items
            .map { "\($0.done ? "[x]" : "[ ]") \($0.text)" }
            .joined(separator: "\n")
    }

    private func writeTodos(_ items: [TodoItem],
                            keeping carried: (h: [HighlightAnchor], b: [HighlightAnchor])? = nil) {
        let kept = carried ?? (h: anchors(of: highlights), b: anchors(of: bolds))
        rebuildText(items)
        let h = rebuilt(from: kept.h)
        let b = rebuilt(from: kept.b)
        if highlights != h { highlights = h }
        if bolds != b { bolds = b }
    }

    private func rebuilt(from anchors: [HighlightAnchor]) -> [TextHighlight] {
        var out: [TextHighlight] = []
        for a in anchors {
            guard let r = todoContentRange(a.item) else { continue }
            let length = min(a.length, max(0, r.length - a.offset))
            guard length > 0 else { continue }
            out = out.adding(NSRange(location: r.location + a.offset, length: length))
        }
        return out
    }

    struct HighlightAnchor {
        let item: Int, offset: Int, length: Int
    }

    private func anchors(of marks: [TextHighlight]) -> [HighlightAnchor] {
        guard !marks.isEmpty else { return [] }
        return todoItems.indices.flatMap { i -> [HighlightAnchor] in
            guard let r = todoContentRange(i) else { return [] }
            return marks.compactMap {
                let overlap = NSIntersectionRange($0.range, r)
                guard overlap.length > 0 else { return nil }
                return HighlightAnchor(item: i, offset: overlap.location - r.location,
                                       length: overlap.length)
            }
        }
    }

    func toggleTodo(_ index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].done.toggle()
        writeTodos(items)
    }

    /// 只由条内直接编辑调用。高亮已经被编辑器按全局范围平移过了
    /// (后面条目的位置也一并挪好), 这里再按锚点重定位反而会把它算丢。
    func setTodoText(_ index: Int, _ newText: String) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].text = newText
        rebuildText(items)
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
        // 删掉这条自己的标记, 它后面的条目整体前移一位
        func dropped(_ list: [HighlightAnchor]) -> [HighlightAnchor] {
            list.filter { $0.item != index }
                .map { HighlightAnchor(item: $0.item > index ? $0.item - 1 : $0.item,
                                       offset: $0.offset, length: $0.length) }
        }
        let carried = (h: dropped(anchors(of: highlights)), b: dropped(anchors(of: bolds)))
        items.remove(at: index)
        writeTodos(items, keeping: carried)
    }

    /// 第 index 条待办的文字在 text 里的范围 (不含 "[ ] " 前缀和行首空格)
    func todoContentRange(_ index: Int) -> NSRange? {
        var offset = 0, item = 0
        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if item == index {
                    let lead = (line as NSString).range(of: trimmed).location
                    var prefix = 0
                    for p in ["[x] ", "[X] ", "[ ] "] where trimmed.hasPrefix(p) {
                        prefix = 4
                        break
                    }
                    let length = (trimmed as NSString).length - prefix
                    guard length > 0 else { return nil }
                    return NSRange(location: offset + lead + prefix, length: length)
                }
                item += 1
            }
            offset += lineLength + 1
        }
        return nil
    }

    /// 文字便签 Markdown 里的任务行: 按行号切换 "- [ ]" ↔ "- [x]"
    func toggleTaskLine(_ lineIndex: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        if let r = line.range(of: "- [ ] ") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "- [x] ")
        } else if let r = line.range(of: "- [x] ") ?? line.range(of: "- [X] ") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "- [ ] ")
        } else {
            return
        }
        text = lines.joined(separator: "\n")
    }
}

// MARK: - 历史归档

struct ArchivedNote: Codable, Identifiable {
    let id: UUID
    let text: String
    let kind: NoteKind
    let theme: NoteTheme
    let highlights: [TextHighlight]
    let bolds: [TextHighlight]
    let deletedAt: Date

    init(id: UUID, text: String, kind: NoteKind, theme: NoteTheme,
         highlights: [TextHighlight] = [], bolds: [TextHighlight] = [], deletedAt: Date) {
        self.id = id
        self.text = text
        self.kind = kind
        self.theme = theme
        self.highlights = highlights
        self.bolds = bolds
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text, kind, theme, highlights, bolds, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        kind = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text
        theme = try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        highlights = try ranges(.highlights)
        bolds = try ranges(.bolds)
        deletedAt = try c.decode(Date.self, forKey: .deletedAt)
    }
}

// MARK: - 存储

final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    @Published private(set) var archived: [ArchivedNote] = []
    private var cancellables: [UUID: AnyCancellable] = [:]
    private var saveWorkItem: DispatchWorkItem?

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var fileURL: URL { dir.appendingPathComponent("notes.json") }
    private var historyURL: URL { dir.appendingPathComponent("history.json") }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
            notes.forEach(observe)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? decoder.decode([ArchivedNote].self, from: data) {
            archived = decoded
        }
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

    /// 删除时归档: 有内容的便签移入历史
    func archive(_ note: Note) {
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        archived.insert(
            ArchivedNote(id: UUID(), text: note.text, kind: note.kind,
                         theme: note.theme, highlights: note.highlights,
                         bolds: note.bolds, deletedAt: Date()),
            at: 0)
        saveHistory()
    }

    /// 从历史中取回 (返回归档内容, 由调用方重建便签)
    func unarchive(_ id: UUID) -> ArchivedNote? {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return nil }
        let item = archived.remove(at: index)
        saveHistory()
        return item
    }

    func removeArchived(_ id: UUID) {
        archived.removeAll { $0.id == id }
        saveHistory()
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(archived) {
            try? data.write(to: historyURL, options: .atomic)
        }
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
