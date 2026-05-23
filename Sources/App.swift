import SwiftUI
import AppKit

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
