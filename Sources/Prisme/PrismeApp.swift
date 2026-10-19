import SwiftUI
import AppKit

@main
struct PrismeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Prisme", id: "main") {
            WorkspaceView().environmentObject(model)
                .frame(minWidth: 900, minHeight: 650)
                .onOpenURL { model.add([$0]) }
        }
        .defaultSize(width: 1100, height: 770)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ajouter des fichiers…") { model.chooseFiles() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.page = .settings; model.showMainWindow() }.keyboardShortcut(",")
            }
        }
        MenuBarExtra("Prisme", systemImage: "triangle.lefthalf.filled") {
            MenuBarContent().environmentObject(model)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.isWorking ? "\(model.activity)…" : "Prisme · vos fichiers, transformés")
        Divider()
        Button("Ouvrir Prisme") { openWindow(id: "main"); model.showMainWindow() }
        Button("Ajouter des fichiers…") { openWindow(id: "main"); model.showMainWindow(); model.chooseFiles() }
        Toggle("Glisser + Maj partout", isOn: $model.globalDragEnabled)
        Button("Historique") { model.page = .history; openWindow(id: "main"); model.showMainWindow() }
        Button("Réglages…") { model.page = .settings; openWindow(id: "main"); model.showMainWindow() }
        Divider()
        Button("Quitter Prisme") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragController: GlobalDragController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        dragController = GlobalDragController(model: AppModel.shared)
        dragController?.start()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { dragController?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showMainWindow()
        return true
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AppModel.shared.add(filenames.map { URL(fileURLWithPath: $0) })
        AppModel.shared.showMainWindow()
        sender.reply(toOpenOrPrint: .success)
    }
}
