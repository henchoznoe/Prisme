import Foundation
import Darwin

extension ConversionEngine {
    func archive(_ action: ConversionAction, files: [URL], options: ConversionOptions) async throws -> [URL] {
        if action.id == "tool.archive.extract" {
            var outputs: [URL] = []
            for file in files {
                outputs.append(try await stagedOutput(source: file, suffix: "-extrait", ext: nil, options: options) { output in
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                    try extractArchive(file, to: output)
                })
            }
            return outputs
        }
        let ext = action.outputExtension ?? "zip"
        return [try await stagedOutput(source: files[0], suffix: "-archive", ext: ext, options: options) { output in
            if ext == "gz" {
                try await runProcess(try executable("gzip"), ["-c", "--", files[0].path], stdoutURL: output)
                return
            }
            let inputs = output.deletingLastPathComponent().appendingPathComponent("inputs")
            try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: false)
            var names: [String] = []
            for file in files {
                try Task.checkCancellation()
                var name = file.lastPathComponent; var count = 2
                while names.contains(name) {
                    name = file.deletingPathExtension().lastPathComponent + " \(count)" + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension)
                    count += 1
                }
                names.append(name)
                try FileManager.default.copyItem(at: file, to: inputs.appendingPathComponent(name))
            }
            if ext == "zip" {
                try await runProcess(try executable("zip"), ["-q", "-r", "-y", output.path, "--"] + names, directory: inputs)
            } else {
                try await runProcess(try executable("tar"), ["-cf", output.path, "-C", inputs.path, "--"] + names)
            }
        }]
    }
}

// libarchive decodes entries, but all filesystem writes remain under our control.
// Symlinks, hard links, device nodes, duplicate files, and parent-directory components are refused.
private struct ArchiveAPI {
    let handle: UnsafeMutableRawPointer
    let new: @convention(c) () -> OpaquePointer?
    let supportFilters: @convention(c) (OpaquePointer) -> Int32
    let supportFormats: @convention(c) (OpaquePointer) -> Int32
    let supportRaw: @convention(c) (OpaquePointer) -> Int32
    let open: @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32
    let next: @convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    let pathname: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    let filetype: @convention(c) (OpaquePointer) -> UInt32
    let symlink: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    let hardlink: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    let read: @convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int) -> Int
    let error: @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    let free: @convention(c) (OpaquePointer) -> Int32

    init() throws {
        guard let handle = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else { throw ConversionError.unsupported("La bibliothèque d’archives de macOS est indisponible.") }
        self.handle = handle
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let value = dlsym(handle, name) else { throw ConversionError.unsupported("Fonction d’archive indisponible : \(name).") }
            return unsafeBitCast(value, to: T.self)
        }
        do {
            new = try symbol("archive_read_new", (@convention(c) () -> OpaquePointer?).self)
            supportFilters = try symbol("archive_read_support_filter_all", (@convention(c) (OpaquePointer) -> Int32).self)
            supportFormats = try symbol("archive_read_support_format_all", (@convention(c) (OpaquePointer) -> Int32).self)
            supportRaw = try symbol("archive_read_support_format_raw", (@convention(c) (OpaquePointer) -> Int32).self)
            open = try symbol("archive_read_open_filename", (@convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32).self)
            next = try symbol("archive_read_next_header", (@convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32).self)
            pathname = try symbol("archive_entry_pathname", (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self)
            filetype = try symbol("archive_entry_filetype", (@convention(c) (OpaquePointer) -> UInt32).self)
            symlink = try symbol("archive_entry_symlink", (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self)
            hardlink = try symbol("archive_entry_hardlink", (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self)
            read = try symbol("archive_read_data", (@convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int) -> Int).self)
            error = try symbol("archive_error_string", (@convention(c) (OpaquePointer) -> UnsafePointer<CChar>?).self)
            free = try symbol("archive_read_free", (@convention(c) (OpaquePointer) -> Int32).self)
        } catch { dlclose(handle); throw error }
    }
}

private func extractArchive(_ source: URL, to directory: URL) throws {
    let api = try ArchiveAPI()
    defer { dlclose(api.handle) }
    guard let archive = api.new() else { throw ConversionError.failed("Impossible d’ouvrir l’archive.") }
    defer { _ = api.free(archive) }
    _ = api.supportFilters(archive); _ = api.supportFormats(archive)
    if ["gz", "bz2", "xz"].contains(source.pathExtension.lowercased()) { _ = api.supportRaw(archive) }
    func failure() -> ConversionError {
        .failed("Archive illisible : " + (api.error(archive).map { String(cString: $0) } ?? source.lastPathComponent))
    }
    guard source.path.withCString({ api.open(archive, $0, 65536) }) == 0 else { throw failure() }
    var entry: OpaquePointer?
    var count = 0; var bytes: Int64 = 0
    var existingFiles = Set<String>()
    let manager = FileManager.default
    while true {
        try Task.checkCancellation()
        let status = api.next(archive, &entry)
        if status == 1 { break }
        guard status >= 0, let entry, let namePointer = api.pathname(entry) else { throw failure() }
        count += 1
        guard count <= 100_000 else { throw ConversionError.unsupported("L’archive contient trop d’entrées (maximum 100 000).") }
        var name = String(cString: namePointer)
        if name == "data", ["gz", "bz2", "xz"].contains(source.pathExtension.lowercased()) { name = source.deletingPathExtension().lastPathComponent }
        guard !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."), !name.contains("\0") else { throw ConversionError.invalid("L’archive contient un chemin dangereux.") }
        let components = name.split(separator: "/").filter { $0 != "." }
        if components.isEmpty { continue }
        guard api.symlink(entry) == nil, api.hardlink(entry) == nil else { throw ConversionError.unsupported("L’archive contient un lien symbolique ou physique. Son extraction est refusée.") }
        let type = api.filetype(entry)
        guard type == 0o100000 || type == 0o040000 else { throw ConversionError.unsupported("L’archive contient un type de fichier spécial non pris en charge.") }
        let relative = components.joined(separator: "/")
        let target = directory.appendingPathComponent(relative)
        if type == 0o040000 {
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
        } else {
            guard existingFiles.insert(relative).inserted else { throw ConversionError.invalid("L’archive contient plusieurs fichiers au même emplacement.") }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard manager.createFile(atPath: target.path, contents: nil) else { throw ConversionError.failed("Impossible d’extraire « \(name) ».") }
            let handle = try FileHandle(forWritingTo: target)
            do {
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    try Task.checkCancellation()
                    let read = buffer.withUnsafeMutableBytes { api.read(archive, $0.baseAddress!, $0.count) }
                    if read == 0 { break }
                    guard read > 0 else { throw failure() }
                    bytes += Int64(read)
                    guard bytes <= 20_000_000_000 else { throw ConversionError.unsupported("L’archive dépasse la limite de 20 Go de données extraites.") }
                    try handle.write(contentsOf: Data(buffer.prefix(read)))
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
        }
    }
    guard count > 0 else { throw ConversionError.invalid("L’archive est vide.") }
}
