import Foundation
import Darwin

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
        self.process = process
    }

    func cancel() {
        lock.lock(); cancelled = true
        let process = process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }
}

// Files avoid pipe-buffer deadlocks for long conversions and large diagnostics.
@discardableResult
func runProcess(_ executable: URL, _ arguments: [String], directory: URL? = nil, stdoutURL: URL? = nil) async throws -> Data {
    let manager = FileManager.default
    let logs = manager.temporaryDirectory.appendingPathComponent("prisme-process-\(UUID().uuidString)")
    try manager.createDirectory(at: logs, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: logs) }
    let output = stdoutURL ?? logs.appendingPathComponent("stdout")
    let errors = logs.appendingPathComponent("stderr")
    guard manager.createFile(atPath: output.path, contents: nil), manager.createFile(atPath: errors.path, contents: nil) else { throw ConversionError.failed("Impossible de créer les fichiers temporaires.") }
    let outHandle = try FileHandle(forWritingTo: output)
    let errHandle = try FileHandle(forWritingTo: errors)
    defer { try? outHandle.close(); try? errHandle.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = outHandle
    process.standardError = errHandle
    process.standardInput = FileHandle.nullDevice
    let running = RunningProcess()
    let status: Int32 = try await withTaskCancellationHandler(operation: {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try running.launch(process) }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
    }, onCancel: { running.cancel() })
    try Task.checkCancellation()
    guard status == 0 else {
        let data = (try? Data(contentsOf: errors)) ?? Data()
        let diagnostic = String(decoding: data.suffix(3000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ConversionError.failed("\(executable.lastPathComponent) a échoué (\(status)). \(diagnostic)")
    }
    return stdoutURL == nil ? try Data(contentsOf: output) : Data()
}
