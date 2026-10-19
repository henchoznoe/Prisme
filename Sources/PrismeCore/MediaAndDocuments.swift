import Foundation
import AppKit
import CoreText
import CoreGraphics

extension ConversionEngine {
    func media(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let ffmpeg = try executable("ffmpeg")
        let ext = action.outputExtension ?? "mp4"
        return [try await stagedOutput(source: file, suffix: "-converti", ext: ext, options: options) { output in
            var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe,crypto,data", "-i", file.path]
            if action.id.hasSuffix(".trim") {
                arguments += ["-ss", String(options.startSeconds), "-t", String(options.durationSeconds)]
            }
            let audioOnly = Self.category(for: file) == .audio || action.id == "tool.video.extractAudio"
            if audioOnly {
                arguments += ["-vn", "-map", "0:a:0"]
                switch ext {
                case "mp3": arguments += ["-c:a", "libmp3lame", "-q:a", String(max(0, Int((1 - options.quality) * 9)))]
                case "m4a": arguments += ["-c:a", "aac", "-b:a", "\(max(64, Int(options.quality * 256)))k"]
                case "wav": arguments += ["-c:a", "pcm_s16le"]
                case "aiff": arguments += ["-c:a", "pcm_s16be"]
                case "flac": arguments += ["-c:a", "flac"]
                case "ogg": arguments += ["-c:a", "libopus", "-b:a", "\(max(48, Int(options.quality * 192)))k"]
                default: throw ConversionError.unsupported("Format audio non pris en charge.")
                }
            } else if ext == "gif" {
                let dimension = min(options.maxDimension, 1920)
                let graph = "fps=12,scale=\(dimension):\(dimension):force_original_aspect_ratio=decrease:force_divisible_by=2,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
                arguments += ["-an", "-filter_complex", graph, "-loop", "0"]
            } else {
                arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn"]
                let crf = max(16, min(40, Int(40 - options.quality * 22)))
                if ext == "webm" {
                    arguments += ["-c:v", "libvpx-vp9", "-crf", String(crf), "-b:v", "0", "-c:a", "libopus", "-b:a", "128k"]
                } else {
                    arguments += ["-c:v", "libx264", "-preset", "medium", "-crf", String(crf), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
                }
                var filters: [String] = []
                if action.id == "tool.video.compress" {
                    filters.append("scale='min(\(options.maxDimension),iw)':'min(\(options.maxDimension),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2")
                }
                filters.append("pad=ceil(iw/2)*2:ceil(ih/2)*2")
                arguments += ["-vf", filters.joined(separator: ","), "-pix_fmt", "yuv420p"]
            }
            arguments += ["-y", output.path]
            try await runProcess(ffmpeg, arguments)
        }]
    }

    func document(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let ext = action.outputExtension ?? "txt"
        return [try await stagedOutput(source: file, suffix: "-converti", ext: ext, options: options) { output in
            if ext == "pdf" {
                let plain: String
                if ["md", "markdown", "txt"].contains(file.pathExtension.lowercased()) {
                    plain = try readText(file)
                } else {
                    let intermediate = output.deletingLastPathComponent().appendingPathComponent("text.txt")
                    try await convertDocument(file, to: intermediate, ext: "txt")
                    plain = try readText(intermediate)
                }
                try writeTextPDF(plain, to: output)
            } else { try await convertDocument(file, to: output, ext: ext) }
        }]
    }
}

private func convertDocument(_ source: URL, to output: URL, ext: String) async throws {
    let sourceExtension = source.pathExtension.lowercased()
    if sourceExtension == ext || (sourceExtension == "markdown" && ext == "md") {
        try FileManager.default.copyItem(at: source, to: output)
        return
    }
    let textutilFormats = ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"]
    if textutilFormats.contains(sourceExtension), ["txt", "rtf", "html", "docx"].contains(ext) {
        try await runProcess(try executable("textutil"), ["-noload", "-nostore", "-convert", ext, "-output", output.path, source.path])
        return
    }
    let inputFormats = ["md": "markdown", "markdown": "markdown", "html": "html", "htm": "html", "docx": "docx", "odt": "odt", "org": "org", "tex": "latex", "rst": "rst", "epub": "epub"]
    let outputFormats = ["md": "markdown", "txt": "plain", "html": "html", "rtf": "rtf", "docx": "docx"]
    let pandoc = try executable("pandoc")
    guard let outputFormat = outputFormats[ext] else { throw ConversionError.unsupported("Format de document non pris en charge : \(ext).") }
    var input = source
    var inputFormat = inputFormats[sourceExtension]
    if sourceExtension == "txt" { inputFormat = "markdown" }
    if inputFormat == nil, textutilFormats.contains(sourceExtension) {
        input = output.deletingLastPathComponent().appendingPathComponent("intermediate.html")
        try await runProcess(try executable("textutil"), ["-noload", "-nostore", "-convert", "html", "-output", input.path, source.path])
        inputFormat = "html"
    }
    guard let inputFormat else { throw ConversionError.unsupported("Pandoc ne peut pas lire ce format de document.") }
    try await runProcess(pandoc, ["--sandbox", "--from", inputFormat, "--to", outputFormat, "--standalone", "--output", output.path, input.path])
}

func readText(_ file: URL) throws -> String {
    let data = try Data(contentsOf: file)
    if let text = String(data: data, encoding: .utf8) { return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text }
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
    throw ConversionError.invalid("Le fichier texte n’est pas encodé en UTF-8 ou UTF-16.")
}

private func writeTextPDF(_ text: String, to output: URL) throws {
    guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { throw ConversionError.failed("Impossible de créer le PDF.") }
    defer { context.closePDF() }
    let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let textBounds = CGRect(x: 44, y: 44, width: 507, height: 754)
    var offset = 0
    while offset < attributed.length {
        try Task.checkCancellation()
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &page, length: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: textBounds, transform: nil), nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        let visible = CTFrameGetVisibleStringRange(frame)
        guard visible.length > 0 else { throw ConversionError.failed("Impossible de paginer ce texte.") }
        offset += visible.length
    }
}
