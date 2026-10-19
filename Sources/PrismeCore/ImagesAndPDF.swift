import Foundation
import AppKit
import ImageIO
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

extension ConversionEngine {
    func image(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let ext = action.outputExtension ?? "png"
        let output = try await stagedOutput(source: file, suffix: action.id.hasPrefix("tool.") ? "-modifie" : "-converti", ext: ext, options: options) { output in
            let avifEncoder = try? executable("avifenc")
            if ext == "webp" || (ext == "avif" && avifEncoder != nil) {
                let intermediate = output.deletingLastPathComponent().appendingPathComponent("source.png")
                try writeImage(readImage(file), to: intermediate, ext: "png", quality: 1)
                if ext == "webp" {
                    try await runProcess(try executable("cwebp"), ["-quiet", "-q", String(Int(options.quality * 100)), intermediate.path, "-o", output.path])
                } else {
                    try await runProcess(try executable("avifenc"), ["-q", String(Int(options.quality * 100)), "--speed", "8", "--jobs", "2", "--", intermediate.path, output.path])
                }
                return
            }
            var image = try readImage(file)
            if action.id == "tool.image.resize" {
                let scale = min(1, Double(options.maxDimension) / Double(max(image.width, image.height)))
                image = try renderedImage(image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
            }
            if action.id == "tool.image.rotate" { image = try renderedImage(image, width: image.height, height: image.width, rotate: true) }
            if ext == "pdf" {
                try writePDFImages([image], to: output)
            } else {
                try writeImage(image, to: output, ext: ext, quality: options.quality)
            }
        }
        return [output]
    }

    func mergePDF(files: [URL], options: ConversionOptions) async throws -> [URL] {
        let output = try await stagedOutput(source: files[0], suffix: "-fusion", ext: "pdf", options: options) { output in
            let merged = PDFDocument()
            for file in files {
                try Task.checkCancellation()
                if Self.category(for: file) == .pdf {
                    let document = try readPDF(file)
                    for index in 0..<document.pageCount {
                        guard let page = document.page(at: index) else { continue }
                        merged.insert(page, at: merged.pageCount)
                    }
                } else {
                    let image = try readImage(file)
                    guard let page = PDFPage(image: NSImage(cgImage: image, size: .zero)) else { throw ConversionError.failed("Impossible de créer la page PDF.") }
                    merged.insert(page, at: merged.pageCount)
                }
            }
            guard merged.write(to: output) else { throw ConversionError.failed("Impossible d’enregistrer le PDF fusionné.") }
        }
        return [output]
    }

    func pdf(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let document = try readPDF(file)
        if action.id == "convert.pdf.txt" {
            return [try await stagedOutput(source: file, suffix: "-texte", ext: "txt", options: options) { output in
                guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversionError.unsupported("Ce PDF ne contient aucun texte sélectionnable. L’OCR n’est pas disponible.") }
                try text.write(to: output, atomically: true, encoding: .utf8)
            }]
        }
        if ["convert.pdf.png", "convert.pdf.jpg", "tool.pdf.split"].contains(action.id) {
            var outputs: [URL] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                let ext = action.outputExtension ?? "pdf"
                outputs.append(try await stagedOutput(source: file, suffix: "-page-\(index + 1)", ext: ext, options: options) { output in
                    if ext == "pdf" {
                        let single = PDFDocument(); single.insert(page, at: 0)
                        guard single.write(to: output) else { throw ConversionError.failed("Impossible d’enregistrer la page PDF.") }
                    } else { try writeImage(renderPDFPage(page, maxDimension: options.maxDimension), to: output, ext: ext, quality: options.quality) }
                })
            }
            return outputs
        }
        return [try await stagedOutput(source: file, suffix: action.id == "tool.pdf.rotate" ? "-rotation" : "-compresse", ext: "pdf", options: options) { output in
            if action.id == "tool.pdf.rotate" {
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    if let page = document.page(at: index) { page.rotation = (page.rotation + 90) % 360 }
                }
                guard document.write(to: output) else { throw ConversionError.failed("Impossible d’enregistrer le PDF.") }
            } else {
                guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { throw ConversionError.failed("Impossible de créer le PDF.") }
                defer { context.closePDF() }
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    guard let page = document.page(at: index) else { continue }
                    let rendered = try renderPDFPage(page, maxDimension: options.maxDimension)
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw ConversionError.failed("Encodage JPEG indisponible.") }
                    CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary)
                    guard CGImageDestinationFinalize(destination), let source = CGImageSourceCreateWithData(data, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConversionError.failed("Impossible de compresser une page.") }
                    var bounds = page.bounds(for: .mediaBox)
                    if page.rotation % 180 != 0 { bounds.size = CGSize(width: bounds.height, height: bounds.width) }
                    bounds.origin = .zero
                    context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &bounds, length: MemoryLayout<CGRect>.size)] as CFDictionary)
                    context.draw(image, in: bounds); context.endPDFPage()
                }
            }
        }]
    }
}

func readImage(_ file: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw ConversionError.invalid("Impossible de lire l’image « \(file.lastPathComponent) ».") }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0, Double(width) * Double(height) <= 200_000_000 else { throw ConversionError.unsupported("Dimensions d’image invalides ou trop importantes (maximum 200 mégapixels).") }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ConversionError.failed("Impossible de décoder l’image.") }
    return image
}

func renderedImage(_ image: CGImage, width: Int, height: Int, rotate: Bool = false, flatten: Bool = false) throws -> CGImage {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.failed("Mémoire insuffisante pour l’image.") }
    if flatten { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    context.interpolationQuality = .high
    if rotate {
        context.translateBy(x: 0, y: CGFloat(height)); context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: height, height: width))
    } else { context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
    guard let result = context.makeImage() else { throw ConversionError.failed("Impossible de générer l’image.") }
    return result
}

func writeImage(_ image: CGImage, to output: URL, ext: String, quality: Double) throws {
    let identifiers = ["png": "public.png", "jpg": "public.jpeg", "heic": "public.heic", "tiff": "public.tiff", "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif", "avif": "public.avif"]
    guard let identifier = identifiers[ext], let destination = CGImageDestinationCreateWithURL(output as CFURL, identifier as CFString, 1, nil) else { throw ConversionError.unsupported("L’encodeur \(ext.uppercased()) n’est pas disponible sur ce Mac.") }
    let encoded = ext == "jpg" ? try renderedImage(image, width: image.width, height: image.height, flatten: true) : image
    CGImageDestinationAddImage(destination, encoded, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ConversionError.failed("Impossible d’enregistrer l’image \(ext.uppercased()).") }
}

func readPDF(_ url: URL) throws -> PDFDocument {
    guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw ConversionError.invalid("PDF vide, illisible ou protégé par un mot de passe.") }
    return document
}

func renderPDFPage(_ page: PDFPage, maxDimension: Int) throws -> CGImage {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else { throw ConversionError.invalid("Dimensions de page PDF invalides.") }
    let scale = Double(maxDimension) / max(bounds.width, bounds.height)
    let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    let thumbnail = page.thumbnail(of: size, for: .mediaBox)
    guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ConversionError.failed("Impossible de rendre une page PDF.") }
    return image
}

func writePDFImages(_ images: [CGImage], to output: URL) throws {
    guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { throw ConversionError.failed("Impossible de créer le PDF.") }
    defer { context.closePDF() }
    for image in images {
        var bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &bounds, length: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.draw(image, in: bounds); context.endPDFPage()
    }
}
