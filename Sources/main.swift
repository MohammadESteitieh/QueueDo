import SwiftUI
import AppKit
import EventKit
import UniformTypeIdentifiers

// MARK: - Models

struct Subtask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false

    enum CodingKeys: String, CodingKey { case id, title, done }
    init(id: UUID = UUID(), title: String, done: Bool = false) {
        self.id = id; self.title = title; self.done = done
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}

struct TodoTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var createdAt: Date = Date()
    var subtasks: [Subtask] = []
    var dueDate: Date? = nil
    var calendarEventID: String? = nil
    var reminderID: String? = nil

    var canComplete: Bool { subtasks.allSatisfy { $0.done } }
    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter { $0.done }.count, subtasks.count)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, createdAt, subtasks, dueDate, calendarEventID, reminderID
    }
    init(id: UUID = UUID(), title: String, notes: String = "",
         createdAt: Date = Date(), subtasks: [Subtask] = [],
         dueDate: Date? = nil, calendarEventID: String? = nil, reminderID: String? = nil) {
        self.id = id; self.title = title; self.notes = notes
        self.createdAt = createdAt; self.subtasks = subtasks
        self.dueDate = dueDate; self.calendarEventID = calendarEventID
        self.reminderID = reminderID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        subtasks = (try? c.decode([Subtask].self, forKey: .subtasks)) ?? []
        dueDate = try? c.decode(Date.self, forKey: .dueDate)
        calendarEventID = try? c.decode(String.self, forKey: .calendarEventID)
        reminderID = try? c.decode(String.self, forKey: .reminderID)
    }
}

struct CompletedTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var createdAt: Date
    var completedAt: Date = Date()
    var subtasks: [Subtask] = []

    enum CodingKeys: String, CodingKey { case id, title, notes, createdAt, completedAt, subtasks }
    init(id: UUID = UUID(), title: String, notes: String = "",
         createdAt: Date, completedAt: Date = Date(), subtasks: [Subtask] = []) {
        self.id = id; self.title = title; self.notes = notes
        self.createdAt = createdAt; self.completedAt = completedAt; self.subtasks = subtasks
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        completedAt = (try? c.decode(Date.self, forKey: .completedAt)) ?? Date()
        subtasks = (try? c.decode([Subtask].self, forKey: .subtasks)) ?? []
    }
}

struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var tasks: [TodoTask] = []
    var completed: [CompletedTask] = []

    enum CodingKeys: String, CodingKey { case id, name, tasks, completed }
    init(id: UUID = UUID(), name: String, tasks: [TodoTask] = [], completed: [CompletedTask] = []) {
        self.id = id; self.name = name; self.tasks = tasks; self.completed = completed
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        tasks = (try? c.decode([TodoTask].self, forKey: .tasks)) ?? []
        completed = (try? c.decode([CompletedTask].self, forKey: .completed)) ?? []
    }
}

// MARK: - Calendar / Reminders

@MainActor
final class CalendarSync {
    static let shared = CalendarSync()
    private let store = EKEventStore()
    private(set) var eventsAuthorized = false
    private(set) var remindersAuthorized = false

    func requestPermissions() async {
        if #available(macOS 14, *) {
            eventsAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
            remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            eventsAuthorized = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
            remindersAuthorized = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
        }
    }

    /// Push task to Reminders (always) and Calendar (only if dueDate).
    /// Returns updated (eventID, reminderID) which the caller persists onto the task.
    @discardableResult
    func upsert(task: TodoTask, categoryName: String) -> (event: String?, reminder: String?) {
        var eventID = task.calendarEventID
        var reminderID = task.reminderID
        let titled = "[\(categoryName)] \(task.title)"

        // Calendar event — only when a due date is set
        if let due = task.dueDate, eventsAuthorized,
           let cal = store.defaultCalendarForNewEvents {
            let event: EKEvent
            if let id = eventID, let existing = store.event(withIdentifier: id) {
                event = existing
            } else {
                event = EKEvent(eventStore: store)
                event.calendar = cal
            }
            event.title = titled
            event.notes = task.notes.isEmpty ? nil : task.notes
            event.startDate = due
            event.endDate = due.addingTimeInterval(30 * 60)
            event.isAllDay = false
            do {
                try store.save(event, span: .thisEvent, commit: true)
                eventID = event.eventIdentifier
            } catch {
                NSLog("QueueDo: calendar save failed: \(error)")
            }
        } else if let id = eventID, let existing = store.event(withIdentifier: id) {
            try? store.remove(existing, span: .thisEvent, commit: true)
            eventID = nil
        }

        // Reminder — always (whether or not dueDate is set)
        if remindersAuthorized, let cal = store.defaultCalendarForNewReminders() {
            let reminder: EKReminder
            if let id = reminderID,
               let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = cal
            }
            reminder.title = titled
            reminder.notes = task.notes.isEmpty ? nil : task.notes
            if let due = task.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: due)
            } else {
                reminder.dueDateComponents = nil
            }
            reminder.isCompleted = false
            do {
                try store.save(reminder, commit: true)
                reminderID = reminder.calendarItemIdentifier
            } catch {
                NSLog("QueueDo: reminder save failed: \(error)")
            }
        }

        return (eventID, reminderID)
    }

    func remove(eventID: String?, reminderID: String?) {
        if let id = eventID, let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
        if let id = reminderID,
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
    }

    func markComplete(reminderID: String?, eventID: String?) {
        if let id = reminderID,
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
        // Calendar event: leave in calendar for record-keeping; do not delete on complete.
        _ = eventID
    }
}

struct AppData: Codable {
    var categories: [Category] = []
    var selectedCategoryID: UUID? = nil

    enum CodingKeys: String, CodingKey { case categories, selectedCategoryID }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = (try? c.decode([Category].self, forKey: .categories)) ?? []
        selectedCategoryID = try? c.decode(UUID.self, forKey: .selectedCategoryID)
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData = AppData()

    private let fileURL: URL

    var selectedCategoryID: UUID? {
        get { data.selectedCategoryID }
        set { data.selectedCategoryID = newValue; save() }
    }
    var selectedCategoryBinding: Binding<UUID?> {
        Binding(get: { self.data.selectedCategoryID },
                set: { self.data.selectedCategoryID = $0; self.save() })
    }

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("QueueDo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("data.json")
        load()
        if data.categories.isEmpty {
            data.categories = [
                Category(name: "Work"),
                Category(name: "School"),
                Category(name: "Personal"),
            ]
        }
        // Validate selectedCategoryID (clear if stale, default to first)
        if let sel = data.selectedCategoryID,
           !data.categories.contains(where: { $0.id == sel }) {
            data.selectedCategoryID = nil
        }
        if data.selectedCategoryID == nil {
            data.selectedCategoryID = data.categories.first?.id
        }
        save()
    }

    func load() {
        guard let bytes = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode(AppData.self, from: bytes) {
            data = decoded
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let bytes = try? enc.encode(data) {
            try? bytes.write(to: fileURL, options: .atomic)
        }
    }

    // Mutations
    func addCategory(name: String) {
        let c = Category(name: name)
        data.categories.append(c)
        data.selectedCategoryID = c.id
        save()
    }

    func renameCategory(_ id: UUID, to name: String) {
        if let i = data.categories.firstIndex(where: { $0.id == id }) {
            data.categories[i].name = name
            save()
        }
    }

    func deleteCategory(_ id: UUID) {
        data.categories.removeAll { $0.id == id }
        if data.selectedCategoryID == id {
            data.selectedCategoryID = data.categories.first?.id
        }
        save()
    }

    func addTask(to categoryID: UUID, title: String, notes: String) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        var task = TodoTask(title: title, notes: notes)
        let ids = CalendarSync.shared.upsert(task: task, categoryName: data.categories[i].name)
        task.calendarEventID = ids.event
        task.reminderID = ids.reminder
        data.categories[i].tasks.append(task)
        save()
    }

    func updateTask(_ task: TodoTask, in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        let ids = CalendarSync.shared.upsert(task: updated, categoryName: data.categories[i].name)
        updated.calendarEventID = ids.event
        updated.reminderID = ids.reminder
        data.categories[i].tasks[j] = updated
        save()
    }

    func removeTask(_ taskID: UUID, in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        if let task = data.categories[i].tasks.first(where: { $0.id == taskID }) {
            CalendarSync.shared.remove(eventID: task.calendarEventID, reminderID: task.reminderID)
        }
        data.categories[i].tasks.removeAll { $0.id == taskID }
        save()
    }

    func moveTasks(in categoryID: UUID, from source: IndexSet, to dest: Int) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        data.categories[i].tasks.move(fromOffsets: source, toOffset: dest)
        save()
    }

    func completeTask(_ taskID: UUID, in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard data.categories[i].tasks[j].canComplete else { return }
        let t = data.categories[i].tasks.remove(at: j)
        CalendarSync.shared.markComplete(reminderID: t.reminderID, eventID: t.calendarEventID)
        let done = CompletedTask(title: t.title, notes: t.notes,
                                 createdAt: t.createdAt, subtasks: t.subtasks)
        data.categories[i].completed.insert(done, at: 0)
        save()
    }

    func addSubtask(to taskID: UUID, in categoryID: UUID, title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty,
              let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        data.categories[i].tasks[j].subtasks.append(Subtask(title: t))
        save()
    }

    func toggleSubtask(_ subtaskID: UUID, in taskID: UUID, categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == taskID }),
              let k = data.categories[i].tasks[j].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        data.categories[i].tasks[j].subtasks[k].done.toggle()
        save()
    }

    func removeSubtask(_ subtaskID: UUID, in taskID: UUID, categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        data.categories[i].tasks[j].subtasks.removeAll { $0.id == subtaskID }
        save()
    }

    func clearHistory(in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        data.categories[i].completed.removeAll()
        save()
    }

    var dataFileURL: URL { fileURL }

    func importJSON(from url: URL) {
        guard let bytes = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode(AppData.self, from: bytes) {
            data = decoded
            if data.selectedCategoryID == nil ||
                !data.categories.contains(where: { $0.id == data.selectedCategoryID }) {
                data.selectedCategoryID = data.categories.first?.id
            }
            save()
        }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var showHistory = false
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let cid = store.selectedCategoryID,
               let cat = store.data.categories.first(where: { $0.id == cid }) {
                if showHistory {
                    HistoryView(category: cat)
                } else {
                    QueueView(category: cat)
                }
            } else {
                VStack(spacing: 10) {
                    Text("No categories yet").foregroundStyle(.secondary)
                    Button("Add category…") { showAddCategory = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategorySheet(name: $newCategoryName) { name in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { store.addCategory(name: trimmed) }
                newCategoryName = ""
            }
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: store.selectedCategoryBinding) {
                ForEach(store.data.categories) { c in
                    Text(c.name).tag(Optional(c.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()

            Button { showHistory.toggle() } label: {
                Image(systemName: showHistory ? "list.bullet" : "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help(showHistory ? "Show queue" : "Show history")

            Menu {
                Button("Add category…") { showAddCategory = true }
                if let cid = store.selectedCategoryID,
                   let cat = store.data.categories.first(where: { $0.id == cid }) {
                    Button("Rename \"\(cat.name)\"…") { renameCurrent(cat) }
                    Button("Delete \"\(cat.name)\"", role: .destructive) { confirmDelete(cat) }
                    Divider()
                    Button("Clear history for \"\(cat.name)\"", role: .destructive) {
                        store.clearHistory(in: cat.id)
                    }
                }
                Divider()
                Button("Export data…") { exportData() }
                Button("Import data…") { importData() }
                Button("Reveal data file in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.dataFileURL])
                }
                Divider()
                Button("Quit QueueDo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(8)
    }

    var footer: some View {
        HStack {
            Text("QueueDo").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let cid = store.selectedCategoryID,
               let cat = store.data.categories.first(where: { $0.id == cid }) {
                Text("\(cat.tasks.count) open · \(cat.completed.count) done")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    func renameCurrent(_ cat: Category) {
        let alert = NSAlert()
        alert.messageText = "Rename category"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(string: cat.name)
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { store.renameCategory(cat.id, to: v) }
        }
    }

    func confirmDelete(_ cat: Category) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(cat.name)\"?"
        alert.informativeText = "All open and completed tasks in this category will be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteCategory(cat.id)
        }
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "queuedo-export.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: store.dataFileURL, to: url)
        }
    }

    func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.importJSON(from: url)
        }
    }
}

struct AddCategorySheet: View {
    @Binding var name: String
    @Environment(\.dismiss) var dismiss
    var onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New category").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { onSave(name); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Queue

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
        comps.day! += 1
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps) ?? Date().addingTimeInterval(86400)
    }
}

// MARK: - History

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

// MARK: - Kanban (window view)

struct KanbanView: View {
    @EnvironmentObject var store: Store
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("QueueDo").font(.title3).fontWeight(.semibold)
                Spacer()
                Button {
                    showAddCategory = true
                } label: {
                    Label("Add category", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Menu {
                    Button("Export data…") { exportData() }
                    Button("Import data…") { importData() }
                    Button("Reveal data file in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.dataFileURL])
                    }
                    Divider()
                    Button("Quit QueueDo") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .frame(width: 34, height: 34)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(12)

            Divider()

            if store.data.categories.isEmpty {
                VStack(spacing: 10) {
                    Text("No categories yet").foregroundStyle(.secondary)
                    Button("Add category…") { showAddCategory = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(store.data.categories) { cat in
                            CategoryColumnView(category: cat)
                                .frame(width: 340)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategorySheet(name: $newCategoryName) { name in
                let t = name.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.addCategory(name: t) }
                newCategoryName = ""
            }
        }
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "queuedo-export.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: store.dataFileURL, to: url)
        }
    }
    func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.importJSON(from: url)
        }
    }
}

struct CategoryColumnView: View {
    @EnvironmentObject var store: Store
    let category: Category
    @State private var newTitle = ""
    @State private var showHistory = false
    @State private var editingTask: TodoTask? = nil
    @State private var expandedTaskIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text(category.name).font(.headline)
                Text("\(category.tasks.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                Spacer()
                Button { showHistory.toggle() } label: {
                    Image(systemName: showHistory ? "list.bullet" : "clock.arrow.circlepath")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(showHistory ? "Show queue" : "Show history")

                Menu {
                    Button("Rename…") { renameColumn() }
                    Button("Delete category", role: .destructive) { confirmDelete() }
                    Divider()
                    Button("Clear history", role: .destructive) {
                        store.clearHistory(in: category.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // Add task field
            HStack(spacing: 8) {
                TextField("Add task…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            // Body
            if showHistory {
                HistoryView(category: category)
            } else if category.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.tertiary)
                    Text("Empty").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
    func renameColumn() {
        let alert = NSAlert()
        alert.messageText = "Rename category"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(string: category.name)
        tf.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { store.renameCategory(category.id, to: v) }
        }
    }
    func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(category.name)\"?"
        alert.informativeText = "All open and completed tasks in this category will be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteCategory(category.id)
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var mainWindow: NSWindow!
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Request Calendar + Reminders access in the background
        Task { await CalendarSync.shared.requestPermissions() }

        // Main window (kanban view)
        let rootHost = NSHostingController(
            rootView: KanbanView()
                .environmentObject(store)
                .frame(minWidth: 480, minHeight: 520)
        )
        mainWindow = NSWindow(contentViewController: rootHost)
        mainWindow.title = "QueueDo"
        mainWindow.setContentSize(NSSize(width: 1100, height: 650))
        mainWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        mainWindow.isReleasedWhenClosed = false
        mainWindow.center()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Menu bar item + popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: RootView()
                .environmentObject(store)
                .frame(width: 380, height: 520)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist",
                                   accessibilityDescription: "QueueDo")
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
        }
    }

    @objc func toggleStatusPopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct QueueDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
