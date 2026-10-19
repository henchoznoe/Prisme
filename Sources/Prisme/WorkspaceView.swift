import SwiftUI
import AppKit
import PrismeCore
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            navigation.padding(.top, 17).padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.page {
                    case .convert: conversionPage
                    case .history: HistoryView()
                    case .settings: PreferencesView()
                    }
                }.padding(.horizontal, 30).padding(.bottom, 22)
                    .frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }
            if model.isWorking { activityBar }
            else if model.page == .convert, !model.files.isEmpty, let action = model.selectedAction { conversionBar(action) }
            else { footer }
        }
        .background(PrismBackdrop())
        .background(WindowChrome().frame(width: 0, height: 0))
        .tint(PrismTheme.accent)
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
        .alert("L’opération n’a pas abouti", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Fermer", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PrismMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Prisme").font(.system(size: 21, weight: .semibold)).tracking(-0.6)
                Text("Un autre format. Le même élan.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Label("Sur votre Mac", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 9).prismGlass(radius: 18)
            GlassIconButton(symbol: "plus", label: "Ajouter des fichiers", action: model.chooseFiles).disabled(model.isWorking)
        }.padding(.horizontal, 30).padding(.top, 32)
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(WorkspacePage.allCases, id: \.self) { page in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.page = page }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol).font(.system(size: 13, weight: .medium))
                        Text(page.rawValue).font(.system(size: 12, weight: .medium))
                        if page == .history, !model.history.isEmpty {
                            Text("\(model.history.count)").font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 2).background(.primary.opacity(0.07), in: Capsule())
                        }
                    }.foregroundStyle(model.page == page ? PrismTheme.accent : .primary.opacity(0.65))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background {
                            if model.page == page {
                                Capsule().fill(PrismTheme.accent.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
                            }
                        }.contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(5).prismGlass(radius: 28, interactive: true)
    }

    private var conversionPage: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Donnez une autre forme à vos fichiers.").font(.system(size: 28, weight: .semibold)).tracking(-0.9)
                Text("Choisissez un format, Prisme s’occupe de la suite.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.files.isEmpty {
                HStack(spacing: 18) {
                    DropArea().frame(maxWidth: .infinity).frame(height: 292)
                    GestureGuide().frame(width: 240, height: 292)
                }
                HStack(spacing: 8) {
                    FormatTag(symbol: "photo", text: "Images")
                    FormatTag(symbol: "waveform", text: "Audio & vidéo")
                    FormatTag(symbol: "doc.text", text: "PDF & documents")
                    FormatTag(symbol: "archivebox", text: "Archives")
                    Spacer()
                    Text("Les originaux restent intacts.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 3)
            } else {
                DropArea().frame(height: 105)
                fileList
                actionPicker
            }
            if let message = model.successMessage {
                Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(PrismTheme.accent)
                    .padding(15).frame(maxWidth: .infinity, alignment: .leading).prismGlass(radius: 16, selected: true)
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(model.files.count) fichier\(model.files.count > 1 ? "s" : "")").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { model.presentQuickPalette?(model.files) } label: { Label("Ouvrir la roue", systemImage: "circle.hexagongrid") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(PrismTheme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8).prismGlass(radius: 16, interactive: true)
                Button("Tout retirer") { model.files = []; model.selectedActionID = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 6)
            }.disabled(model.isWorking)
            ForEach(model.files, id: \.self) { url in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(url.pathExtension.uppercased()).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(.primary.opacity(0.04), in: Capsule())
                    Button { model.files.removeAll { $0 == url }; model.selectedActionID = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Retirer ce fichier").disabled(model.isWorking)
                }.padding(13).prismGlass(radius: 16)
            }
        }
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Opération", selection: $model.mode) {
                Text("Formats").tag(PaletteMode.convert)
                Text("Outils").tag(PaletteMode.tools)
            }.pickerStyle(.segmented).frame(width: 210).onChange(of: model.mode) { _ in model.selectedActionID = nil }
            if model.visibleActions.isEmpty {
                Text("Aucune opération commune à cette sélection. Essayez un fichier seul ou vérifiez les moteurs dans Réglages.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                PrismGlassGroup {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                        ForEach(model.visibleActions) { action in
                            ActionCard(action: action, selected: model.selectedAction?.id == action.id) { model.selectedActionID = action.id }
                        }
                    }
                }
                if let action = model.selectedAction { operationOptions(action) }
            }
        }.disabled(model.isWorking)
    }

    @ViewBuilder private func operationOptions(_ action: ConversionAction) -> some View {
        if action.id.contains("compress") || action.id.hasPrefix("convert.image.") {
            HStack(spacing: 12) {
                Text("Qualité").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $model.quality, in: 0.1...1).frame(maxWidth: 210)
                Text("\(Int(model.quality * 100)) %").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(PrismTheme.accent)
                Spacer()
            }.padding(.top, 3)
        }
        if action.id.contains("resize") {
            HStack {
                Text("Côté le plus long").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Pixels", value: $model.maxDimension, formatter: NumberFormatter()).frame(width: 80).textFieldStyle(.roundedBorder)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        if action.id.contains("trim") {
            HStack(spacing: 12) {
                Text("Début (s)").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("0", value: $model.startSeconds, format: .number).frame(width: 65).textFieldStyle(.roundedBorder)
                Text("Durée (s)").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("10", value: $model.durationSeconds, format: .number).frame(width: 65).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func conversionBar(_ action: ConversionAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").font(.system(size: 16)).foregroundStyle(PrismTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Enregistrer le résultat").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(model.outputFolder.isEmpty ? "À côté de chaque original" : URL(fileURLWithPath: model.outputFolder).lastPathComponent)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            Button("Modifier…", action: model.chooseOutputFolder).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button(action: model.runSelected) {
                HStack(spacing: 10) { Text(action.title); Image(systemName: "arrow.right") }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(LinearGradient(colors: [PrismTheme.accent.opacity(0.85), PrismTheme.accent], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.8))
                    .shadow(color: PrismTheme.accent.opacity(0.25), radius: 9, y: 3)
            }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
        }.padding(15).prismGlass(radius: 23).padding(.horizontal, 30).padding(.bottom, 20)
    }

    private var activityBar: some View {
        HStack(spacing: 13) {
            ProgressView().controlSize(.small)
            Text("\(model.activity)…").font(.system(size: 12))
            Spacer()
            Button("Annuler", action: model.cancel).buttonStyle(.plain).foregroundStyle(PrismTheme.accent).font(.system(size: 11))
        }.padding(18).prismGlass(radius: 20).padding(.horizontal, 30).padding(.bottom, 20)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "circle.inset.filled").font(.system(size: 7)).foregroundStyle(PrismTheme.accent)
            Text("Prisme veille dans la barre de menus").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text("⇧ Formats     ⌘ Outils     ⌃ Actions").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.horizontal, 33).padding(.vertical, 17)
    }
}

struct DropArea: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false
    var body: some View {
        Button(action: model.chooseFiles) {
            VStack(spacing: model.files.isEmpty ? 18 : 9) {
                if model.files.isEmpty { FloatingFiles().frame(height: 105) }
                else { Image(systemName: "plus.circle").font(.system(size: 23, weight: .light)).foregroundStyle(PrismTheme.accent) }
                VStack(spacing: 7) {
                    Text(model.files.isEmpty ? "Déposez vos fichiers" : "Ajouter d’autres fichiers")
                        .font(.system(size: model.files.isEmpty ? 21 : 13, weight: .semibold)).tracking(-0.4)
                    if model.files.isEmpty { Text("ou parcourez votre Mac").font(.system(size: 12)).foregroundStyle(PrismTheme.accent) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .prismGlass(radius: 28, selected: targeted, interactive: true)
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(PrismTheme.accent.opacity(targeted ? 0.8 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5])).padding(7))
                .contentShape(RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain).disabled(model.isWorking)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !model.isWorking else { return false }
                FileDropReader.read(providers) { model.add($0) }
                return true
            }
    }
}

private struct FloatingFiles: View {
    var body: some View {
        PrismGlassGroup {
            ZStack {
                file("doc.text", color: .indigo).rotationEffect(.degrees(-17)).offset(x: -47, y: 4)
                file("waveform", color: PrismTheme.accent).rotationEffect(.degrees(16)).offset(x: 47, y: 5)
                file("photo", color: PrismTheme.accent).offset(y: -5)
            }
        }.accessibilityHidden(true)
    }
    private func file(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 27, weight: .light)).foregroundStyle(color)
            .frame(width: 69, height: 82).prismGlass(radius: 18)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.45), lineWidth: 0.6))
            .shadow(color: color.opacity(0.09), radius: 10, y: 9)
    }
}

private struct GestureGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "cursorarrow.motionlines").font(.system(size: 27, weight: .light)).foregroundStyle(PrismTheme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Au bout du geste.").font(.system(size: 17, weight: .semibold)).tracking(-0.4)
                Text("Glissez un fichier, puis appuyez sur une touche pour ouvrir la roue.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            VStack(spacing: 9) {
                row("⇧", "Formats", "arrow.triangle.2.circlepath")
                row("⌘", "Outils", "slider.horizontal.3")
                row("⌃", "Actions", "square.and.arrow.up")
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).prismGlass(radius: 28)
    }
    private func row(_ key: String, _ title: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            KeyCap(text: key)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

struct ActionCard: View {
    let action: ConversionAction
    let selected: Bool
    let activate: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol).font(.system(size: 19, weight: .light)).frame(width: 26).foregroundStyle(PrismTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    Text(action.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(PrismTheme.accent) }
            }.padding(14).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).prismGlass(radius: 18, selected: selected, interactive: true)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PrismTheme.accent.opacity(hovering ? 0.3 : 0), lineWidth: 1))
            .onHover { hovering = $0 }
    }
}

private struct FormatTag: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8).prismGlass(radius: 16)
    }
}

enum FileDropReader {
    static func read(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            completion(urls)
        }
    }
}
