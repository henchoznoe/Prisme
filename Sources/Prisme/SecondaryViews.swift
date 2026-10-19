import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Tout ce qui a pris forme.").font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                    Text("Vos 100 dernières opérations, enregistrées sur ce Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.history.isEmpty {
                    Button("Effacer l’historique") { model.clearHistory() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).help("Efface la liste, conserve tous les fichiers")
                }
            }
            if model.history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(PrismTheme.accent)
                    Text("Votre prochaine conversion commence ici.").font(.system(size: 14)).foregroundStyle(.secondary)
                    Button("Ajouter des fichiers…") { model.chooseFiles() }
                }.frame(maxWidth: .infinity).padding(.vertical, 90)
            }
            ForEach(model.history) { entry in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark").font(.system(size: 13)).foregroundStyle(PrismTheme.accent).padding(10).background(PrismTheme.accent.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.action).font(.system(size: 13, weight: .medium))
                        Text(entry.sources.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        Text(entry.date, format: .dateTime.day().month(.wide).hour().minute()).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.reveal(entry.outputs) } label: { Image(systemName: "folder").font(.system(size: 15)) }
                        .buttonStyle(.plain).foregroundStyle(PrismTheme.accent).help("Afficher les résultats dans le Finder")
                }.padding(18).prismGlass(radius: 20)
            }
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                Text("À votre façon.").font(.system(size: 32, weight: .semibold)).tracking(-0.8)
                Text("Quelques réglages. Et le reste suit.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            settingsGroup("AU QUOTIDIEN") {
                Text("Prisme reste active dans la barre de menus quand vous fermez cette fenêtre, sans icône dans le Dock. Pour l’arrêter, choisissez « Quitter Prisme » dans son menu.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Toggle("Palette pendant un glisser-déposer", isOn: $model.globalDragEnabled).toggleStyle(.switch)
                Text("Glissez un fichier depuis le Finder, appuyez sur Maj, puis déposez-le sur un format. ⌘ ouvre les outils, ⌃ les actions. Échap ferme la palette.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                triggerPicker("Formats", selection: $model.conversionTrigger, used: [model.toolsTrigger, model.actionsTrigger])
                triggerPicker("Outils", selection: $model.toolsTrigger, used: [model.conversionTrigger, model.actionsTrigger])
                triggerPicker("Actions", selection: $model.actionsTrigger, used: [model.conversionTrigger, model.toolsTrigger])
                Picker("Apparence de la roue", selection: $model.wheelAppearance) {
                    Text("Liquid Glass").tag("glass")
                    Text("Opaque").tag("solid")
                }.pickerStyle(.segmented)
                Divider().opacity(0.3)
                Toggle("Afficher les résultats dans le Finder", isOn: $model.showResults).toggleStyle(.switch)
            }
            settingsGroup("DOSSIER DE SORTIE") {
                HStack {
                    Image(systemName: "folder").foregroundStyle(PrismTheme.accent)
                    Text(model.outputFolder.isEmpty ? "À côté du fichier d’origine" : model.outputFolder).lineLimit(2).truncationMode(.middle)
                    Spacer()
                    Button("Choisir…") { model.chooseOutputFolder() }
                    if !model.outputFolder.isEmpty { Button("Réinitialiser") { model.outputFolder = "" } }
                }
                Text("Les originaux restent intacts. Un nom unique est créé si le résultat existe déjà.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            settingsGroup("MOTEURS DE CONVERSION") {
                dependency("API Apple", detail: "Images, PDF, textes, sous-titres et archives", installed: true)
                Divider().opacity(0.3)
                dependency("FFmpeg", detail: "Conversions audio et vidéo", installed: ToolLocator.path("ffmpeg") != nil)
                dependency("Pandoc", detail: "Markdown, DOCX et EPUB", installed: ToolLocator.path("pandoc") != nil)
                dependency("WebP", detail: "Encodeur cwebp", installed: ToolLocator.path("cwebp") != nil)
                dependency("AVIF", detail: "Encodeur avifenc (selon les capacités natives)", installed: ToolLocator.path("avifenc") != nil)
                Text("Pour ajouter les moteurs optionnels avec Homebrew :").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                HStack {
                    Text("brew install ffmpeg pandoc webp libavif").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("brew install ffmpeg pandoc webp libavif", forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copier la commande")
                }.padding(13).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                Text("Prisme ne télécharge aucun moteur et n’envoie aucun fichier. Les options nécessitant un moteur absent sont masquées.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
            HStack(alignment: .top, spacing: 14) {
                PrismMark(size: 45)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prisme 0.2.1").font(.system(size: 13, weight: .medium))
                    Text("Un atelier de conversion indépendant, en Swift.\nSans compte, sans abonnement, sans limite d’utilisation.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
        }.font(.system(size: 12))
    }

    private func triggerPicker(_ title: String, selection: Binding<String>, used: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(DragKey.all.filter { !used.contains($0) }, id: \.self) { key in Text(DragKey.label(key)).tag(key) }
        }.frame(maxWidth: 330)
    }

    private func dependency(_ title: String, detail: String, installed: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Label(installed ? "Disponible" : "À installer", systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 10)).foregroundStyle(installed ? PrismTheme.accent : .secondary)
        }.padding(.vertical, 4)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(PrismTheme.accent)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).prismGlass(radius: 24)
    }
}
