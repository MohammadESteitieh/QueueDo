import SwiftUI
import Foundation

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
