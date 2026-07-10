import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: NoteStore
    var onRestore: (ArchivedNote) -> Void
    @State private var pendingDelete: ArchivedNote?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 按删除日期分组, 新的在前
    private var grouped: [(day: Date, notes: [ArchivedNote])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.archived) { cal.startOfDay(for: $0.deletedAt) }
        return dict.keys.sorted(by: >).map { day in
            (day, dict[day]!.sorted { $0.deletedAt > $1.deletedAt })
        }
    }

    var body: some View {
        Group {
            if store.archived.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text("还没有历史便签")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("删除的便签会按日期归档到这里")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.day) { group in
                        Section {
                            ForEach(group.notes) { item in
                                row(item)
                            }
                        } header: {
                            Text(Self.dayFormatter.string(from: group.day))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, minHeight: 320)
        .alert("彻底删除这条历史?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete { store.removeArchived(item.id) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("彻底删除后无法找回。")
        }
    }

    @ViewBuilder
    private func row(_ item: ArchivedNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 主题色圆点 + 类型
            Circle()
                .fill(Color(nsColor: item.theme.bar))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color(nsColor: item.theme.accent).opacity(0.4), lineWidth: 1))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind == .todo ? "✅ 待办事项" : "📝 文字便签")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Self.timeFormatter.string(from: item.deletedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                content(item)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    onRestore(item)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("恢复成便签")

                Button {
                    pendingDelete = item
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("彻底删除")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func content(_ item: ArchivedNote) -> some View {
        if item.kind == .todo {
            // 待办: 逐条显示完成状态
            let items = Note(text: item.text, kind: .todo).todoItems
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, todo in
                    HStack(spacing: 5) {
                        Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundStyle(todo.done
                                ? Color(nsColor: item.theme.accent).opacity(0.8)
                                : Color.secondary.opacity(0.6))
                        Text(todo.text)
                            .font(.system(size: 13))
                            .strikethrough(todo.done)
                            .foregroundStyle(todo.done ? .secondary : .primary)
                    }
                }
            }
        } else {
            Text(item.text)
                .font(.system(size: 13))
                .lineLimit(8)
                .foregroundStyle(.primary)
        }
    }
}
