import SwiftUI

struct EditTaskSheet: View {
    @State var task: TodoTask
    @Environment(\.dismiss) var dismiss
    var onSave: (TodoTask) -> Void

    @State private var hasDueDate: Bool

    init(task: TodoTask, onSave: @escaping (TodoTask) -> Void) {
        _task = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit task").font(.headline)
            TextField("Title", text: $task.title).textFieldStyle(.roundedBorder)

            Toggle("Has due date", isOn: $hasDueDate)
                .onChange(of: hasDueDate) { _, newVal in
                    if newVal && task.dueDate == nil {
                        task.dueDate = nextDefaultDueDate()
                    } else if !newVal {
                        task.dueDate = nil
                    }
                }
            if hasDueDate {
                DatePicker("Due", selection: Binding(
                    get: { task.dueDate ?? nextDefaultDueDate() },
                    set: { task.dueDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            }

            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $task.notes)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(task); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func nextDefaultDueDate() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        if let currentDay = comps.day {
            comps.day = currentDay + 1
        }
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps) ?? Date().addingTimeInterval(86400)
    }
}

struct HistoryView: View {
    let category: Category

    var body: some View {
        if category.completed.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.tertiary)
                Text("No completed tasks yet").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(category.completed) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).strikethrough(color: .secondary)
                        HStack(spacing: 6) {
                            Text(t.completedAt, style: .date)
                            Text(t.completedAt, style: .time)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        if !t.notes.isEmpty {
                            Text(t.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
