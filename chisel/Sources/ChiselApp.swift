import AppKit
import SwiftUI

@main
struct ChiselApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Chisel") {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть…") { AppModel.shared.pickFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Папка для результатов…") { AppModel.shared.chooseOutputFolder() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Убрать все файлы") { AppModel.shared.clearAll() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Вставить") { AppModel.shared.pasteFromClipboard() }
                    .keyboardShortcut("v", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Окно должно быть пустым: тёмный фон, прозрачная титульная полоса,
        // на ней только светофор и название «Chisel».
        DispatchQueue.main.async { self.styleWindows() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.add(urls)
    }

    private func styleWindows() {
        for window in NSApp.windows {
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Theme.nsBackground
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.title = "Chisel"
            window.isMovableByWindowBackground = true
        }
    }
}
