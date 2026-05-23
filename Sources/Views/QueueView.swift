import SwiftUI

struct QueueView: View {
    @EnvironmentObject var store: Store
    let category: Category
    @State private var newTitle: String = ""
    @State private var editingTask: TodoTask? = nil
    @State private var expandedTaskIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Add task to \(category.name)…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)

            if category.tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Queue is empty").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(category.tasks.enumerated()), id: \.element.id) { idx, task in
                        TaskRow(categoryID: category.id,
                                task: task,
                                isTop: idx == 0,
                                isExpanded: expandedTaskIDs.contains(task.id),
                                onToggleExpand: { toggleExpand(task.id) },
                                onEdit: { editingTask = task })
                    }
                    .onMove { src, dst in
                        store.moveTasks(in: category.id, from: src, to: dst)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editingTask) { task in
            EditTaskSheet(task: task) { updated in
                store.updateTask(updated, in: category.id)
            }
        }
    }

    func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTask(to: category.id, title: t, notes: "")
        newTitle = ""
    }

    func toggleExpand(_ id: UUID) {
        if expandedTaskIDs.contains(id) { expandedTaskIDs.remove(id) }
        else { expandedTaskIDs.insert(id) }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let categoryID: UUID
    let task: TodoTask
    let isTop: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onEdit: () -> Void

    @State private var newSubtaskText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: complete) {
                    Image(systemName: completeIcon)
                        .foregroundStyle(completeColor)
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!task.canComplete)
                .help(task.canComplete ? "Mark complete" : "Complete subtasks first")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Button(action: onToggleExpand) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Hide subtasks" : "Show subtasks")

                        Text(task.title)
                            .font(.body)
                            .fontWeight(isTop ? .semibold : .regular)
                        if !task.subtasks.isEmpty {
                            let p = task.subtaskProgress
                            Text("\(p.done)/\(p.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        if let due = task.dueDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                Text(dueChipText(due))
                                    .font(.caption)
                            }
                            .foregroundStyle(dueColor(due))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(dueColor(due).opacity(0.15), in: Capsule())
                        }
                    }
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Edit…", action: onEdit)
                    if task.canComplete {
                        Button("Complete", action: complete)
                    } else {
                        Button("Complete (subtasks unfinished)") {}.disabled(true)
                    }
                    Button(isExpanded ? "Hide subtasks" : "Show subtasks", action: onToggleExpand)
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.removeTask(task.id, in: categoryID)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onEdit() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.subtasks) { sub in
                        HStack(spacing: 8) {
                            Button {
                                store.toggleSubtask(sub.id, in: task.id, categoryID: categoryID)
                            } label: {
                                Image(systemName: sub.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(sub.done ? Color.accentColor : .secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            Text(sub.title)
                                .font(.callout)
                                .strikethrough(sub.done, color: .secondary)
                                .foregroundStyle(sub.done ? .secondary : .primary)
                            Spacer()
                            Button {
                                store.removeSubtask(sub.id, in: task.id, categoryID: categoryID)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Remove subtask")
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        TextField("Add subtask…", text: $newSubtaskText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .onSubmit(addSubtask)
                        if !newSubtaskText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: addSubtask).buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.leading, 36)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }

    var completeIcon: String {
        if !task.canComplete { return "circle.dotted" }
        return isTop ? "circle.inset.filled" : "circle"
    }
    var completeColor: Color {
        if !task.canComplete { return .secondary.opacity(0.6) }
        return isTop ? Color.accentColor : .secondary
    }

    func complete() {
        guard task.canComplete else { return }
        store.completeTask(task.id, in: categoryID)
    }

    func addSubtask() {
        let t = newSubtaskText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addSubtask(to: task.id, in: categoryID, title: t)
        newSubtaskText = ""
    }

    private func dueChipText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return "Today " + d.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInTomorrow(d) {
            return "Tomorrow " + d.formatted(date: .omitted, time: .shortened)
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: d)).day ?? 0
        if days < 0 {
            return d.formatted(date: .abbreviated, time: .shortened)
        }
        if days <= 7 {
            return d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    private func dueColor(_ d: Date) -> Color {
        if d < Date() { return .red }
        if Calendar.current.isDateInToday(d) { return .orange }
        return .secondary
    }
}
