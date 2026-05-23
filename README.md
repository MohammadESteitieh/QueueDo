# QueueDo 📅✅

QueueDo is a lightweight, elegant task management application for macOS that blends a Kanban-style overview with a quick-access menu bar popover. It focuses on "getting things out of your head" and into a structured queue, with automatic synchronization to macOS Calendar and Reminders.

## ✨ Features

- **Dual Interface**:
  - **Kanban View**: A full-window experience to manage multiple categories side-by-side.
  - **Menu Bar Popover**: Quick entry and status checks without leaving your current app.
- **System Integration**:
  - **Automatic Reminders**: Every task is pushed to macOS Reminders.
  - **Calendar Sync**: Tasks with due dates are automatically created as Calendar events.
  - **Bi-directional Logic**: Marking a task complete in QueueDo updates the system Reminder.
- **Hierarchical Tasks**: Support for subtasks to break down larger goals.
- **Category Management**: Organize your life into "Work", "School", "Personal", or custom categories.
- **Data Portability**: Export and import your data via JSON files.

## 🚀 Installation & Build

### Prerequisites
- macOS 14.0 or later.
- Xcode Command Line Tools (for `swiftc` and `codesign`).

### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/QueueDo.git
   cd QueueDo
   ```
2. Run the build script:
   ```bash
   bash build.sh
   ```
   *The script will compile the Swift source, create the app bundle, sign it ad-hoc, and install it directly into your `/Applications` folder.*

## 🛠 Technical Architecture

QueueDo is built using a modern Swift stack:
- **SwiftUI**: For a declarative, responsive user interface.
- **EventKit**: For deep integration with the macOS Calendar and Reminders databases.
- **ObservableObject (Store)**: A centralized state management system ensuring data consistency across the Kanban and Popover views.
- **JSON Persistence**: Simple, transparent local storage for all application data.

## 📋 Usage Tips
- **Quick Add**: Use the popover to quickly dump tasks into your current category.
- **Subtasks**: Double-click a task to edit it or expand it to add sub-steps. A task cannot be marked complete until all its subtasks are finished.
- **Due Dates**: Add a due date to a task to see it appear on your macOS Calendar.

## 📜 License
MIT License
