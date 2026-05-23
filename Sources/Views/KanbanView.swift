import SwiftUI

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
