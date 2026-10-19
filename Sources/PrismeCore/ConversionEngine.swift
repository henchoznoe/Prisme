import Foundation
import UniformTypeIdentifiers
import ImageIO

public enum FileCategory: String, CaseIterable, Sendable {
    case image, video, audio, pdf, document, spreadsheet, subtitle, archive, folder, other
}

public struct ConversionAction: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let outputExtension: String?

    public init(id: String, title: String, detail: String, symbol: String, outputExtension: String? = nil) {
        self.id = id; self.title = title; self.detail = detail
        self.symbol = symbol; self.outputExtension = outputExtension
    }
}

public struct ConversionOptions: Sendable {
    public var outputDirectory: URL?
    public var quality: Double = 0.85
    public var maxDimension: Int = 1920
    public var startSeconds: Double = 0
    public var durationSeconds: Double = 10
    public init() {}
}

public enum ConversionError: LocalizedError {
    case invalid(String), unsupported(String), missingTool(String), failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let text), .unsupported(let text), .failed(let text): return text
        case .missingTool(let name): return "L’outil \(name) est nécessaire. Installez-le avec Homebrew : brew install \(name.lowercased())."
        }
    }
}

public struct ConversionEngine: Sendable {
    public init() {}

    public static func isTool(_ action: ConversionAction) -> Bool { action.id.hasPrefix("tool.") }

    public static func category(for url: URL) -> FileCategory {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .folder }
        let ext = url.pathExtension.lowercased()
        if ["pdf"].contains(ext) { return .pdf }
        if ["csv", "tsv", "json"].contains(ext) { return .spreadsheet }
        if ["srt", "vtt"].contains(ext) { return .subtitle }
        if ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"].contains(ext) { return .archive }
        if ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp", "avif", "ico", "icns", "dng", "cr2", "nef", "arw"].contains(ext) { return .image }
        if ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "mts", "m2ts"].contains(ext) { return .video }
        if ["mp3", "m4a", "wav", "flac", "aiff", "aif", "ogg", "opus", "aac", "wma", "caf"].contains(ext) { return .audio }
        if ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "md", "markdown", "org", "tex", "rst", "epub"].contains(ext) { return .document }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .text) { return .document }
        }
        return .other
    }

    public static func actions(for files: [URL]) -> [ConversionAction] {
        guard !files.isEmpty else { return [] }
        let categories = Set(files.map(category))
        var actions: [ConversionAction] = []
        func format(_ category: String, _ ext: String, _ title: String, _ detail: String, _ symbol: String) {
            actions.append(.init(id: "convert.\(category).\(ext)", title: title, detail: detail, symbol: symbol, outputExtension: ext))
        }
        func tool(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ ext: String? = nil) {
            actions.append(.init(id: "tool.\(id)", title: title, detail: detail, symbol: symbol, outputExtension: ext))
        }
        if categories == [.image] {
            for (ext, title) in [("png", "PNG"), ("jpg", "JPEG"), ("heic", "HEIC"), ("tiff", "TIFF"), ("bmp", "BMP"), ("gif", "GIF"), ("pdf", "PDF"), ("webp", "WebP"), ("avif", "AVIF")] {
                format("image", ext, title, ext == "webp" ? "Image fixe · cwebp" : ext == "avif" ? "Image fixe · macOS ou avifenc" : "Image fixe · conversion native", "photo")
            }
            tool("image.compress", "Compresser", "JPEG avec qualité réglable", "arrow.down.right.and.arrow.up.left", "jpg")
            tool("image.resize", "Redimensionner", "Réduire le plus grand côté, sans agrandir", "arrow.up.left.and.arrow.down.right", "png")
            tool("image.rotate", "Tourner à droite", "Rotation de 90° · sortie PNG", "rotate.right", "png")
        }
        if categories == [.pdf] {
            format("pdf", "png", "PNG", "Une image par page", "photo")
            format("pdf", "jpg", "JPEG", "Une image par page · qualité réglable", "photo")
            format("pdf", "txt", "Texte", "Extraire le texte sélectionnable, sans OCR", "text.alignleft")
            tool("pdf.split", "Séparer les pages", "Un PDF par page", "rectangle.split.2x1", "pdf")
            tool("pdf.rotate", "Tourner les pages", "Rotation de 90° de chaque page", "rotate.right", "pdf")
            tool("pdf.compress", "Alléger le PDF", "Pages en images JPEG · texte non sélectionnable", "arrow.down.right.and.arrow.up.left", "pdf")
        }
        if categories.isSubset(of: [.image, .pdf]), files.count > 1 {
            tool("pdf.merge", "Fusionner en PDF", "Dans l’ordre de la sélection", "doc.on.doc", "pdf")
        }
        if categories == [.video] {
            for ext in ["mp4", "mov", "webm", "gif"] { format("video", ext, ext.uppercased(), "Conversion vidéo · FFmpeg", "film") }
            tool("video.compress", "Compresser la vidéo", "MP4 H.264 · taille et qualité réglables", "arrow.down.right.and.arrow.up.left", "mp4")
            tool("video.trim", "Découper la vidéo", "Début et durée réglables · sortie MP4", "scissors", "mp4")
            tool("video.extractAudio", "Extraire l’audio", "Piste audio en M4A", "waveform", "m4a")
        }
        if categories == [.audio] {
            for ext in ["mp3", "m4a", "wav", "flac", "aiff", "ogg"] { format("audio", ext, ext.uppercased(), ext == "ogg" ? "Ogg Opus · FFmpeg" : "Conversion audio · FFmpeg", "waveform") }
            tool("audio.trim", "Découper l’audio", "Début et durée réglables · sortie M4A", "scissors", "m4a")
        }
        if categories == [.document] {
            for ext in ["txt", "rtf", "html", "docx", "md"] { format("document", ext, ext.uppercased(), "Textutil ou Pandoc · mise en page variable", "doc.text") }
            format("document", "pdf", "PDF", "Texte paginé · mise en page simplifiée", "doc.richtext")
        }
        if categories == [.spreadsheet] {
            format("table", "csv", "CSV", "Valeurs séparées par des virgules", "tablecells")
            format("table", "tsv", "TSV", "Valeurs séparées par des tabulations", "tablecells")
            format("table", "json", "JSON", "Objets utilisant la première ligne comme en-têtes", "curlybraces")
        }
        if categories == [.subtitle] {
            for ext in ["srt", "vtt", "txt"] { format("subtitle", ext, ext.uppercased(), ext == "txt" ? "Texte sans minutage" : "Conserver les minutages des sous-titres", "captions.bubble") }
        }
        tool("archive.zip", "Créer une archive ZIP", "Fichiers et dossiers sélectionnés", "archivebox", "zip")
        tool("archive.tar", "Créer une archive TAR", "Archive sans compression", "archivebox", "tar")
        if files.count == 1, categories != [.folder] {
            tool("archive.gz", "Compresser en GZIP", "Un fichier · compression sans perte", "archivebox", "gz")
        }
        if categories == [.archive] {
            tool("archive.extract", "Extraire l’archive", "Nouveau dossier · liens et chemins dangereux refusés", "tray.and.arrow.down")
        }
        let ffmpegAvailable = (try? executable("ffmpeg")) != nil
        let pandocAvailable = (try? executable("pandoc")) != nil
        let nativeImageTypes = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let textutilInputs: Set<String> = ["txt", "rtf", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"]
        return actions.filter { action in
            if action.id == "convert.image.webp" { return (try? executable("cwebp")) != nil }
            if action.id == "convert.image.avif" { return nativeImageTypes.contains("public.avif") || (try? executable("avifenc")) != nil }
            if action.id.hasPrefix("convert.video.") || action.id.hasPrefix("tool.video.") || action.id.hasPrefix("convert.audio.") || action.id.hasPrefix("tool.audio.") { return ffmpegAvailable }
            if action.id.hasPrefix("convert.document."), !pandocAvailable {
                if action.outputExtension == "md" { return false }
                if action.outputExtension == "pdf" {
                    return files.allSatisfy { textutilInputs.contains($0.pathExtension.lowercased()) || ["md", "markdown"].contains($0.pathExtension.lowercased()) }
                }
                return files.allSatisfy { textutilInputs.contains($0.pathExtension.lowercased()) }
            }
            return true
        }
    }

    public func perform(_ action: ConversionAction, files: [URL], options: ConversionOptions) async throws -> [URL] {
        guard !files.isEmpty else { throw ConversionError.invalid("Sélectionnez au moins un fichier.") }
        guard Self.actions(for: files).contains(where: { $0.id == action.id }) else { throw ConversionError.unsupported("Cette opération ne correspond pas aux fichiers sélectionnés.") }
        guard options.quality.isFinite, (0.01...1).contains(options.quality), (1...32768).contains(options.maxDimension), options.startSeconds.isFinite, options.startSeconds >= 0, options.durationSeconds.isFinite, options.durationSeconds > 0 else {
            throw ConversionError.invalid("Vérifiez la qualité, les dimensions et les minutages.")
        }
        let task = Task.detached(priority: .userInitiated) { try await self.run(action, files: files, options: options) }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private func run(_ action: ConversionAction, files: [URL], options: ConversionOptions) async throws -> [URL] {
        try Task.checkCancellation()
        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else { throw ConversionError.invalid("Le fichier « \(file.lastPathComponent) » est introuvable.") }
        }
        if action.id.hasPrefix("tool.archive.") { return try await archive(action, files: files, options: options) }
        if action.id == "tool.pdf.merge" { return try await mergePDF(files: files, options: options) }
        var results: [URL] = []
        for file in files {
            try Task.checkCancellation()
            switch Self.category(for: file) {
            case .image: results += try await image(action, file: file, options: options)
            case .pdf: results += try await pdf(action, file: file, options: options)
            case .video, .audio: results += try await media(action, file: file, options: options)
            case .document: results += try await document(action, file: file, options: options)
            case .spreadsheet: results += try await table(action, file: file, options: options)
            case .subtitle: results += try await subtitle(action, file: file, options: options)
            default: throw ConversionError.unsupported("Format non pris en charge : \(file.pathExtension).")
            }
        }
        return results
    }
}

// Every writer works in a private directory on the destination volume. Only completed files are moved into view.
func stagedOutput(source: URL, suffix: String, ext: String?, options: ConversionOptions, writer: (URL) async throws -> Void) async throws -> URL {
    let manager = FileManager.default
    let directory = options.outputDirectory ?? source.deletingLastPathComponent()
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let workspace = directory.appendingPathComponent(".prisme-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: workspace, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: workspace) }
    let staged = workspace.appendingPathComponent("result" + (ext.map { "." + $0 } ?? ""))
    try await writer(staged)
    try Task.checkCancellation()
    guard manager.fileExists(atPath: staged.path) else { throw ConversionError.failed("La conversion n’a produit aucun fichier.") }
    let base = source.deletingPathExtension().lastPathComponent + suffix
    var index = 1
    while true {
        let name = base + (index == 1 ? "" : " \(index)") + (ext.map { "." + $0 } ?? "")
        let destination = directory.appendingPathComponent(name)
        if manager.fileExists(atPath: destination.path) { index += 1; continue }
        do { try manager.moveItem(at: staged, to: destination); return destination }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { index += 1 }
    }
}

func executable(_ name: String) throws -> URL {
    let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] + environmentPaths {
        let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    throw ConversionError.missingTool(name)
}
