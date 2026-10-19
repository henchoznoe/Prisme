import AppKit
import SwiftUI
import PrismeCore

enum WorkspacePage: String, CaseIterable {
    case convert = "Convertir"
    case history = "Historique"
    case settings = "Réglages"

    var symbol: String {
        switch self {
        case .convert: return "square.stack.3d.up"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum PaletteMode: String, CaseIterable {
    case convert = "Convertir", tools = "Outils", actions = "Actions"
    var key: String { self == .convert ? "⇧" : self == .tools ? "⌘" : "⌃" }
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let action: String
    let sources: [String]
    let outputs: [String]
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var page: WorkspacePage = .convert
    @Published var files: [URL] = []
    @Published var selectedActionID: String?
    @Published var mode: PaletteMode = .convert
    @Published var isWorking = false
    @Published var activity = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var history: [HistoryEntry] = []
    @Published var quality = 0.85
    @Published var maxDimension = 1920
    @Published var startSeconds = 0.0
    @Published var durationSeconds = 10.0
    @Published var quickFiles: [URL] = []
    @Published var quickMode: PaletteMode = .convert
    @Published var quickHoveredID: String?
    @AppStorage("globalDragEnabled") var globalDragEnabled = true
    @AppStorage("showResults") var showResults = true
    @AppStorage("outputFolder") var outputFolder = ""
    @AppStorage("conversionTrigger") var conversionTrigger = "shift"
    @AppStorage("toolsTrigger") var toolsTrigger = "command"
    @AppStorage("actionsTrigger") var actionsTrigger = "control"
    @AppStorage("wheelAppearance") var wheelAppearance = "glass"
    var dismissQuickPalette: (() -> Void)?
    var presentQuickPalette: (([URL]) -> Void)?
    var openMainWindow: (() -> Void)?
    private var work: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "history"),
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = entries
        }
    }

    var allActions: [ConversionAction] { ConversionEngine.actions(for: files) }
    var visibleActions: [ConversionAction] {
        allActions.filter { mode == .tools ? ConversionEngine.isTool($0) : !ConversionEngine.isTool($0) }
    }
    var selectedAction: ConversionAction? { visibleActions.first { $0.id == selectedActionID } ?? visibleActions.first }
    var quickActions: [ConversionAction] {
        ConversionEngine.actions(for: quickFiles).filter {
            quickMode == .tools ? ConversionEngine.isTool($0) : !ConversionEngine.isTool($0)
        }
    }

    func add(_ urls: [URL]) {
        guard !isWorking else { return }
        files = Array(NSOrderedSet(array: files + urls.filter(\.isFileURL))) as? [URL] ?? files
        selectedActionID = nil
        errorMessage = nil
        successMessage = nil
        page = .convert
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url.path }
    }

    func runSelected() {
        guard let action = selectedAction else { return }
        run(action, on: files)
    }

    func run(_ action: ConversionAction, on inputs: [URL]) {
        guard !isWorking, !inputs.isEmpty else { return }
        dismissQuickPalette?()
        isWorking = true
        errorMessage = nil
        successMessage = nil
        activity = action.title
        var options = ConversionOptions()
        options.quality = quality
        options.maxDimension = maxDimension
        options.startSeconds = startSeconds
        options.durationSeconds = durationSeconds
        options.outputDirectory = outputFolder.isEmpty ? nil : URL(fileURLWithPath: outputFolder, isDirectory: true)
        let capturedOptions = options
        work = Task {
            do {
                let outputs = try await ConversionEngine().perform(action, files: inputs, options: capturedOptions)
                try Task.checkCancellation()
                history.insert(HistoryEntry(id: UUID(), date: Date(), action: action.title,
                    sources: inputs.map(\.path), outputs: outputs.map(\.path)), at: 0)
                history = Array(history.prefix(100))
                persistHistory()
                successMessage = "\(outputs.count) fichier\(outputs.count > 1 ? "s" : "") créé\(outputs.count > 1 ? "s" : ""). Vos originaux sont conservés."
                if showResults { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
            } catch is CancellationError {
                errorMessage = "Opération annulée."
            } catch {
                errorMessage = error.localizedDescription
                showMainWindow()
            }
            isWorking = false
            activity = ""
            work = nil
        }
    }

    func cancel() { work?.cancel() }

    func reveal(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { errorMessage = "Ces fichiers ne sont plus à leur emplacement d’origine." }
        else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func clearHistory() { history = []; persistHistory() }
    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "history") }
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Prisme" }) {
            window.makeKeyAndOrderFront(nil)
        } else { openMainWindow?() }
    }

    func fileAction(_ action: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        dismissQuickPalette?()
        switch action {
        case "reveal": NSWorkspace.shared.activateFileViewerSelecting(urls)
        case "path": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL])
        case "airdrop": NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        case "terminal":
            let directory = urls[0].hasDirectoryPath ? urls[0] : urls[0].deletingLastPathComponent()
            if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        default: break
        }
    }
}

enum ToolLocator {
    static func path(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
