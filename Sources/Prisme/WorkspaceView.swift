import SwiftUI
import AppKit
import PrismeCore
import UniformTypeIdentifiers

let mint = Color(red: 0.64, green: 0.93, blue: 0.80)
private let canvas = Color(red: 0.055, green: 0.075, blue: 0.085)
private let card = Color.white.opacity(0.035)

struct PrismMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(mint.opacity(0.10))
            Image(systemName: "triangle.lefthalf.filled")
                .font(.system(size: size * 0.5, weight: .light)).foregroundStyle(mint)
        }.frame(width: size, height: size)
    }
}

struct WorkspaceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.065)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(model.page.rawValue.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(mint).frame(width: 5, height: 5)
                        Text("100 % sur votre Mac").font(.system(size: 11))
                    }.foregroundStyle(.secondary)
                }.padding(.horizontal, 36).padding(.top, 31).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.page {
                        case .convert: conversionPage
                        case .history: HistoryView()
                        case .settings: PreferencesView()
                        }
                    }.padding(.horizontal, 36).padding(.bottom, 30)
                        .frame(maxWidth: 1100, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                if model.isWorking { activityBar }
            }
        }
        .background(canvas)
        .tint(mint)
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
        .alert("L’opération n’a pas abouti", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Fermer", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                PrismMark()
                Text("Prisme").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.top, 44).padding(.bottom, 44)
            Text("VOTRE ATELIER").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary).padding(.bottom, 14)
            ForEach(WorkspacePage.allCases, id: \.self) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.symbol).font(.system(size: 15)).frame(width: 20)
                        Text(page.rawValue).font(.system(size: 13, weight: model.page == page ? .medium : .regular))
                        Spacer()
                        if page == .history && !model.history.isEmpty {
                            Text("\(model.history.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(model.page == page ? mint : .white.opacity(0.5))
                        .padding(.horizontal, 13).padding(.vertical, 12)
                        .background(model.page == page ? mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, -13).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 21, weight: .light)).foregroundStyle(mint.opacity(0.8))
                Text("Un geste suffit.").font(.system(size: 13, weight: .medium))
                Text("Glissez un fichier, puis appuyez sur Maj pour ouvrir la palette.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                HStack(spacing: 6) {
                    KeyCap(text: "⇧"); Text("pendant le glisser").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(15).background(card, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, -6)
            HStack {
                Text("PRISME").tracking(2)
                Spacer()
                Text("0.1.0")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.25)).padding(.top, 26)
        }.padding(.horizontal, 25).padding(.bottom, 24).frame(width: 205)
            .background(Color.white.opacity(0.018))
    }

    private var conversionPage: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 11) {
                Text("Changez de format.\nGardez le fil.").font(.system(size: 39, weight: .medium, design: .rounded)).tracking(-1.5).lineSpacing(-1)
                Text("Des fichiers transformés, sans détour et sans envoi en ligne.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(.bottom, 4)
            HStack(spacing: 7) {
                FeaturePill(symbol: "photo", title: "Images")
                FeaturePill(symbol: "waveform", title: "Audio & vidéo")
                FeaturePill(symbol: "doc", title: "PDF & textes")
                FeaturePill(symbol: "archivebox", title: "Archives")
            }
            DropArea().frame(height: model.files.isEmpty ? 205 : 116)
            if !model.files.isEmpty {
                fileList
                actionPicker
            } else {
                HStack(alignment: .top, spacing: 22) {
                    HintStep(number: "01", title: "Déposez", detail: "Un fichier, un dossier ou tout un lot.")
                    HintStep(number: "02", title: "Choisissez", detail: "Les options s’adaptent à vos fichiers.")
                    HintStep(number: "03", title: "C’est prêt", detail: "Le résultat apparaît à côté de l’original.")
                }.padding(.top, 3)
            }
            if let message = model.successMessage {
                Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(mint)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(model.files.count) FICHIER\(model.files.count > 1 ? "S" : "")").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Button { model.presentQuickPalette?(model.files) } label: {
                    Label("Ouvrir la roue", systemImage: "circle.hexagongrid")
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(mint).padding(.trailing, 12).disabled(model.isWorking)
                Button("Tout retirer") { model.files = []; model.selectedActionID = nil }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.isWorking)
            }
            ForEach(model.files, id: \.self) { url in
                HStack(spacing: 11) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                        Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(url.pathExtension.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundStyle(mint.opacity(0.8))
                    Button { model.files.removeAll { $0 == url }; model.selectedActionID = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Retirer ce fichier").disabled(model.isWorking)
                }.padding(11).background(card, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                ForEach([PaletteMode.convert, .tools], id: \.self) { mode in
                    Button { model.mode = mode; model.selectedActionID = nil } label: {
                        Text(mode.rawValue).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundStyle(model.mode == mode ? mint : .secondary)
                            .background(model.mode == mode ? mint.opacity(0.1) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            if model.visibleActions.isEmpty {
                Text("Aucune opération commune à cette sélection. Essayez un fichier seul ou vérifiez les moteurs dans Réglages.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 9)], spacing: 9) {
                    ForEach(model.visibleActions) { action in
                        ActionCard(action: action, selected: model.selectedAction?.id == action.id) { model.selectedActionID = action.id }
                    }
                }
                if let action = model.selectedAction {
                    operationOptions(action)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESTINATION").font(.system(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                            Text(model.outputFolder.isEmpty ? "À côté de chaque original" : URL(fileURLWithPath: model.outputFolder).lastPathComponent)
                                .font(.system(size: 11)).lineLimit(1)
                        }
                        Button { model.chooseOutputFolder() } label: { Image(systemName: "folder").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Changer de dossier")
                        Spacer()
                        Button { model.runSelected() } label: {
                            HStack(spacing: 9) { Text(action.title); Image(systemName: "arrow.right") }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(canvas)
                                .padding(.horizontal, 18).padding(.vertical, 12).background(mint, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(model.isWorking).keyboardShortcut(.return, modifiers: .command)
                    }.padding(.top, 5)
                }
            }
        }.disabled(model.isWorking)
    }

    @ViewBuilder private func operationOptions(_ action: ConversionAction) -> some View {
        if action.id.contains("compress") || action.id.hasPrefix("convert.image.") {
            HStack {
                Text("Qualité").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $model.quality, in: 0.1...1).frame(maxWidth: 200)
                Text("\(Int(model.quality * 100)) %").font(.system(size: 10, design: .monospaced)).foregroundStyle(mint)
                Spacer()
            }
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

    private var activityBar: some View {
        HStack(spacing: 13) {
            ProgressView().controlSize(.small)
            Text("\(model.activity)…").font(.system(size: 12))
            Spacer()
            Button("Annuler") { model.cancel() }.buttonStyle(.plain).foregroundStyle(mint).font(.system(size: 11))
        }.padding(18).background(mint.opacity(0.05))
    }
}

struct DropArea: View {
    @EnvironmentObject var model: AppModel
    @State private var targeted = false
    var body: some View {
        Button { model.chooseFiles() } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down").font(.system(size: model.files.isEmpty ? 30 : 23, weight: .ultraLight)).foregroundStyle(mint)
                Text(model.files.isEmpty ? "Déposez vos fichiers ici" : "Ajouter d’autres fichiers")
                    .font(.system(size: model.files.isEmpty ? 17 : 13, weight: .medium, design: .rounded))
                if model.files.isEmpty {
                    HStack(spacing: 4) { Text("ou").foregroundStyle(.secondary); Text("parcourez votre Mac").foregroundStyle(mint); Image(systemName: "arrow.up.right").foregroundStyle(mint) }.font(.system(size: 11))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(mint.opacity(targeted ? 0.09 : 0.025), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(mint.opacity(targeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(model.isWorking)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                guard !model.isWorking else { return false }
                FileDropReader.read(providers) { model.add($0) }
                return true
            }
    }
}

struct ActionCard: View {
    let action: ConversionAction
    let selected: Bool
    let activate: () -> Void
    var body: some View {
        Button(action: activate) {
            HStack(spacing: 11) {
                Image(systemName: action.symbol).font(.system(size: 17, weight: .light)).frame(width: 23).foregroundStyle(selected ? mint : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? mint : .white.opacity(0.85))
                    Text(action.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(mint) }
            }.padding(13).frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                .background(selected ? mint.opacity(0.075) : card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? mint.opacity(0.4) : .white.opacity(0.05), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct FeaturePill: View {
    let symbol: String
    let title: String
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10).padding(.vertical, 7).background(card, in: Capsule())
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            .frame(minWidth: 26, minHeight: 23).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.08)))
    }
}

private struct HintStep: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(mint.opacity(0.5))
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
