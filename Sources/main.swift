import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Models

struct Subtask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
}

struct TodoTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var createdAt: Date = Date()
    var subtasks: [Subtask] = []

    var canComplete: Bool { subtasks.allSatisfy { $0.done } }
    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter { $0.done }.count, subtasks.count)
    }
}

struct CompletedTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var createdAt: Date
    var completedAt: Date = Date()
    var subtasks: [Subtask] = []
}

struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var tasks: [TodoTask] = []
    var completed: [CompletedTask] = []
}

struct AppData: Codable {
    var categories: [Category] = []
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData = AppData()
    @Published var selectedCategoryID: UUID?

    private let fileURL: URL

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
                Category(name: "RAship"),
                Category(name: "Company"),
            ]
            save()
        }
        selectedCategoryID = data.categories.first?.id
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
        selectedCategoryID = c.id
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
        if selectedCategoryID == id {
            selectedCategoryID = data.categories.first?.id
        }
        save()
    }

    func addTask(to categoryID: UUID, title: String, notes: String) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
        data.categories[i].tasks.append(TodoTask(title: title, notes: notes))
        save()
    }

    func updateTask(_ task: TodoTask, in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }),
              let j = data.categories[i].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.categories[i].tasks[j] = task
        save()
    }

    func removeTask(_ taskID: UUID, in categoryID: UUID) {
        guard let i = data.categories.firstIndex(where: { $0.id == categoryID }) else { return }
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
            selectedCategoryID = data.categories.first?.id
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
            Picker("", selection: $store.selectedCategoryID) {
                ForEach(store.data.categories) { c in
                    Text(c.name).tag(Optional(c.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()

            Button { showHistory.toggle() } label: {
                Image(systemName: showHistory ? "list.bullet" : "clock.arrow.circlepath")
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
            HStack {
                TextField("Add task to \(category.name)…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button(action: addTask) { Image(systemName: "plus") }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)

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
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(!task.canComplete)
                .help(task.canComplete ? "Mark complete" : "Complete subtasks first")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Button(action: onToggleExpand) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Hide subtasks" : "Show subtasks")

                        Text(task.title)
                            .fontWeight(isTop ? .semibold : .regular)
                        if !task.subtasks.isEmpty {
                            let p = task.subtaskProgress
                            Text("\(p.done)/\(p.total)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
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
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onEdit() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.subtasks) { sub in
                        HStack(spacing: 6) {
                            Button {
                                store.toggleSubtask(sub.id, in: task.id, categoryID: categoryID)
                            } label: {
                                Image(systemName: sub.done ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(sub.done ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            Text(sub.title)
                                .strikethrough(sub.done, color: .secondary)
                                .foregroundStyle(sub.done ? .secondary : .primary)
                            Spacer()
                            Button {
                                store.removeSubtask(sub.id, in: task.id, categoryID: categoryID)
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove subtask")
                        }
                        .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                        TextField("Add subtask…", text: $newSubtaskText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .onSubmit(addSubtask)
                        if !newSubtaskText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: addSubtask).buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 2)
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
}

struct EditTaskSheet: View {
    @State var task: TodoTask
    @Environment(\.dismiss) var dismiss
    var onSave: (TodoTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit task").font(.headline)
            TextField("Title", text: $task.title).textFieldStyle(.roundedBorder)
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $task.notes)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(task); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
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

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var mainWindow: NSWindow!
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Main window
        let rootHost = NSHostingController(
            rootView: RootView()
                .environmentObject(store)
                .frame(minWidth: 380, minHeight: 520)
        )
        mainWindow = NSWindow(contentViewController: rootHost)
        mainWindow.title = "QueueDo"
        mainWindow.setContentSize(NSSize(width: 420, height: 560))
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
