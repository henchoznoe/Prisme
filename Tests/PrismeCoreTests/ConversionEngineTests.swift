import XCTest
import AppKit
import ImageIO
import PDFKit
@testable import PrismeCore

final class ConversionEngineTests: XCTestCase {
    var root: URL!
    let engine = ConversionEngine()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("prisme-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func action(_ id: String, _ files: [URL]) throws -> ConversionAction {
        try XCTUnwrap(ConversionEngine.actions(for: files).first { $0.id == id }, "Missing action \(id)")
    }

    func text(_ name: String, _ contents: String) throws -> URL {
        let file = root.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func image(_ name: String = "image.png") throws -> URL {
        let file = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        try writeImage(try XCTUnwrap(context.makeImage()), to: file, ext: "png", quality: 0.8)
        return file
    }

    func testCategoriesAndActionFiltering() throws {
        XCTAssertEqual(ConversionEngine.category(for: root), .folder)
        XCTAssertEqual(ConversionEngine.category(for: root.appendingPathComponent("A.MP4")), .video)
        XCTAssertTrue(ConversionEngine.actions(for: []).isEmpty)
        let files = [try text("a.txt", "hello"), try image()]
        XCTAssertFalse(ConversionEngine.actions(for: files).contains { $0.id.hasPrefix("convert.") })
        XCTAssertTrue(ConversionEngine.actions(for: files).allSatisfy(ConversionEngine.isTool))
    }

    func testImageResizeRotateAndNoOverwrite() async throws {
        let file = try image()
        let original = try Data(contentsOf: file)
        var options = ConversionOptions(); options.maxDimension = 30
        let resized = try await engine.perform(action("tool.image.resize", [file]), files: [file], options: options)[0]
        let bitmap = try readImage(resized)
        XCTAssertEqual(bitmap.width, 30); XCTAssertEqual(bitmap.height, 15)
        let rotated = try await engine.perform(action("tool.image.rotate", [file]), files: [file], options: .init())[0]
        XCTAssertEqual(try readImage(rotated).width, 40)
        XCTAssertEqual(try readImage(rotated).height, 80)
        let again = try await engine.perform(action("tool.image.rotate", [file]), files: [file], options: .init())[0]
        XCTAssertNotEqual(again, rotated)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".prisme-") })
    }

    func testNativeImageFormats() async throws {
        let file = try image()
        for ext in ["png", "jpg", "tiff", "bmp", "gif", "heic", "pdf"] {
            let result = try await engine.perform(action("convert.image.\(ext)", [file]), files: [file], options: .init())[0]
            if ext == "pdf" { XCTAssertEqual(try XCTUnwrap(PDFDocument(url: result)).pageCount, 1) }
            else { XCTAssertEqual(try readImage(result).width, 80) }
        }
    }

    func testPDFMergeSplitAndCompress() async throws {
        let first = try image()
        let second = try image("second.png")
        let merged = try await engine.perform(action("tool.pdf.merge", [first, second]), files: [first, second], options: .init())[0]
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: merged)).pageCount, 2)
        let pages = try await engine.perform(action("tool.pdf.split", [merged]), files: [merged], options: .init())
        XCTAssertEqual(pages.count, 2)
        for page in pages { XCTAssertEqual(try XCTUnwrap(PDFDocument(url: page)).pageCount, 1) }
        var options = ConversionOptions(); options.maxDimension = 100
        let pngs = try await engine.perform(action("convert.pdf.png", [merged]), files: [merged], options: options)
        XCTAssertEqual(pngs.count, 2)
        XCTAssertLessThanOrEqual(try readImage(pngs[0]).width, 100)
        let compressed = try await engine.perform(action("tool.pdf.compress", [merged]), files: [merged], options: options)[0]
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: compressed)).pageCount, 2)
        let rotated = try await engine.perform(action("tool.pdf.rotate", [merged]), files: [merged], options: options)[0]
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: rotated)?.page(at: 0)).rotation, 90)
    }

    func testDocumentToPDFAndTextExtraction() async throws {
        let source = try text("notes.txt", "Bonjour Prisme\n" + String(repeating: "Une ligne de texte.\n", count: 100))
        let pdf = try await engine.perform(action("convert.document.pdf", [source]), files: [source], options: .init())[0]
        let document = try XCTUnwrap(PDFDocument(url: pdf))
        XCTAssertGreaterThan(document.pageCount, 1)
        let extracted = try await engine.perform(action("convert.pdf.txt", [pdf]), files: [pdf], options: .init())[0]
        XCTAssertTrue(try readText(extracted).contains("Bonjour Prisme"))
        let rtf = try await engine.perform(action("convert.document.rtf", [source]), files: [source], options: .init())[0]
        XCTAssertTrue(try readText(rtf).hasPrefix("{\\rtf"))
        let docx = try await engine.perform(action("convert.document.docx", [source]), files: [source], options: .init())[0]
        let txt = try await engine.perform(action("convert.document.txt", [docx]), files: [docx], options: .init())[0]
        XCTAssertTrue(try readText(txt).contains("Bonjour Prisme"))
    }

    func testCSVQuotedFieldsRoundTrip() async throws {
        let csv = try text("table.csv", "nom,description\r\nAlice,\"Bonjour, monde\"\r\nBob,\"Deux\nLignes et \"\"guillemets\"\"\"\r\n")
        let tsv = try await engine.perform(action("convert.table.tsv", [csv]), files: [csv], options: .init())[0]
        XCTAssertEqual(try parseDelimited(readText(tsv), separator: "\t"), [["nom", "description"], ["Alice", "Bonjour, monde"], ["Bob", "Deux\nLignes et \"guillemets\""]])
        let json = try await engine.perform(action("convert.table.json", [csv]), files: [csv], options: .init())[0]
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [[String: String]])
        XCTAssertEqual(objects[1]["description"], "Deux\nLignes et \"guillemets\"")
        let roundTrip = try await engine.perform(action("convert.table.csv", [json]), files: [json], options: .init())[0]
        XCTAssertEqual(try parseDelimited(readText(roundTrip), separator: ",").count, 3)
    }

    func testCSVRejectsMalformedAndUnevenRows() async throws {
        XCTAssertThrowsError(try parseDelimited("a,b\n\"unfinished", separator: ","))
        XCTAssertThrowsError(try parseDelimited("\"done\"bad", separator: ","))
        let file = try text("uneven.csv", "a,b\n1,2,3\n")
        do { _ = try await engine.perform(action("convert.table.json", [file]), files: [file], options: .init()); XCTFail("Uneven rows accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("colonnes")) }
    }

    func testSubtitleTimingsAndUnicode() async throws {
        let srt = try text("captions.srt", "1\n00:00:01,125 --> 00:00:03,500\nÉté à Fribourg\n\n2\n00:00:04,000 --> 00:00:05,250\nDeuxième ligne\n")
        let vtt = try await engine.perform(action("convert.subtitle.vtt", [srt]), files: [srt], options: .init())[0]
        XCTAssertTrue(try readText(vtt).contains("00:00:01.125 --> 00:00:03.500"))
        let restored = try await engine.perform(action("convert.subtitle.srt", [vtt]), files: [vtt], options: .init())[0]
        XCTAssertTrue(try readText(restored).contains("Été à Fribourg"))
        XCTAssertEqual(try parseSubtitles(readText(restored))[1].end, 5.25)
        let txt = try await engine.perform(action("convert.subtitle.txt", [vtt]), files: [vtt], options: .init())[0]
        XCTAssertFalse(try readText(txt).contains("-->"))
    }

    func testArchiveRoundTrips() async throws {
        let file = try text("bonjour.txt", "Bonjour les archives !")
        for ext in ["zip", "tar", "gz"] {
            let archive = try await engine.perform(action("tool.archive.\(ext)", [file]), files: [file], options: .init())[0]
            let directory = try await engine.perform(action("tool.archive.extract", [archive]), files: [archive], options: .init())[0]
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(try readText(files[0]), "Bonjour les archives !")
        }
    }

    func testArchiveRefusesTraversalAndLinksAndCleansTemporaryOutput() async throws {
        for (name, type, link) in [("../escape.txt", "0", ""), ("link", "2", "../../outside")] {
            let archive = root.appendingPathComponent(UUID().uuidString + ".tar")
            try tarFixture(name: name, type: type, link: link).write(to: archive)
            do { _ = try await engine.perform(action("tool.archive.extract", [archive]), files: [archive], options: .init()); XCTFail("Unsafe archive accepted") }
            catch { XCTAssertTrue(error is ConversionError) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape.txt").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".prisme-") || $0.hasSuffix("-extrait") })
    }

    func testInvalidOptionsAndActionAreRejected() async throws {
        let file = try image()
        var options = ConversionOptions(); options.quality = .nan
        do { _ = try await engine.perform(action("convert.image.png", [file]), files: [file], options: options); XCTFail("NaN accepted") }
        catch { XCTAssertTrue(error is ConversionError) }
        do { _ = try await engine.perform(.init(id: "bad", title: "", detail: "", symbol: ""), files: [file], options: .init()); XCTFail("Unknown action accepted") }
        catch { XCTAssertTrue(error is ConversionError) }
    }

    func testProcessCancellation() async throws {
        let process = Task { try await runProcess(URL(fileURLWithPath: "/bin/sleep"), ["10"]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date(); process.cancel()
        do { _ = try await process.value; XCTFail("Cancelled process succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testFFmpegConversionsWhenInstalled() async throws {
        guard let ffmpeg = try? executable("ffmpeg") else { throw XCTSkip("FFmpeg not installed") }
        let source = root.appendingPathComponent("clip.mp4")
        try await runProcess(ffmpeg, ["-nostdin", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=red:s=80x40:r=12", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-y", source.path])
        var options = ConversionOptions(); options.maxDimension = 40; options.durationSeconds = 0.2
        for id in ["convert.video.mp4", "convert.video.mov", "convert.video.webm", "convert.video.gif", "tool.video.compress", "tool.video.trim", "tool.video.extractAudio"] {
            let output = try await engine.perform(action(id, [source]), files: [source], options: options)[0]
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
            if id == "tool.video.extractAudio" {
                for ext in ["mp3", "m4a", "wav", "flac", "aiff", "ogg"] {
                    let audio = try await engine.perform(action("convert.audio.\(ext)", [output]), files: [output], options: options)[0]
                    XCTAssertGreaterThan(try Data(contentsOf: audio).count, 0)
                }
            }
        }
        let image = try image()
        for ext in ["webp", "avif"] {
            let output = try await engine.perform(action("convert.image.\(ext)", [image]), files: [image], options: options)[0]
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
        }
    }

    func testPandocConversionsWhenInstalled() async throws {
        guard (try? executable("pandoc")) != nil else { throw XCTSkip("Pandoc not installed") }
        let markdown = try text("notes.md", "# Bonjour\n\nTexte **important** et accents : été.\n")
        for ext in ["html", "docx", "rtf", "txt"] {
            let output = try await engine.perform(action("convert.document.\(ext)", [markdown]), files: [markdown], options: .init())[0]
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
            if ["docx", "rtf"].contains(ext) {
                let restored = try await engine.perform(action("convert.document.md", [output]), files: [output], options: .init())[0]
                XCTAssertTrue(try readText(restored).contains("Bonjour"))
            }
        }
    }
}

private func tarFixture(name: String, type: String, link: String) -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    func field(_ value: String, _ offset: Int, _ length: Int) {
        for (index, byte) in value.utf8.prefix(length).enumerated() { header[offset + index] = byte }
    }
    field(name, 0, 100); field("0000644", 100, 8); field("0000000", 108, 8); field("0000000", 116, 8)
    field("00000000000", 124, 12); field("00000000000", 136, 12)
    field("        ", 148, 8); field(type, 156, 1); field(link, 157, 100); field("ustar\0", 257, 6); field("00", 263, 2)
    let checksum = header.reduce(0) { $0 + Int($1) }
    field(String(format: "%06o", checksum) + "\0 ", 148, 8)
    return Data(header + [UInt8](repeating: 0, count: 1024))
}
