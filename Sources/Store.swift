import SwiftUI
import Foundation

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
