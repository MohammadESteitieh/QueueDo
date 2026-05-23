import SwiftUI
import AppKit

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
