import Foundation
import Darwin

public enum ProcessRunnerError: LocalizedError, Equatable {
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "处理超时（\(Int(seconds)) 秒），已终止"
        }
    }
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// 逐行收集管道输出。ffmpeg 的 -progress 是逐行 key=value，需要流式读取。
private final class OutputCollector: @unchecked Sendable {
    private let handle: FileHandle
    private let onLine: (@Sendable (String) -> Void)?
    private let lock = NSLock()
    private var buffer = Data()
    private var allData = Data()
    private var scanOffset = 0

    init(handle: FileHandle, onLine: (@Sendable (String) -> Void)?) {
        self.handle = handle
        self.onLine = onLine
    }

    func start() {
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard let self else { return }
            if data.isEmpty {
                fileHandle.readabilityHandler = nil
                return
            }
            self.append(data)
        }
    }

    private func append(_ data: Data) {
        var lines: [String] = []
        lock.lock()
        allData.append(data)
        buffer.append(data)

        // 从上次扫描位置继续找换行，避免无换行的大输出反复从头扫描。
        var searchIndex = buffer.index(buffer.startIndex, offsetBy: scanOffset)
        while let newline = buffer[searchIndex...].firstIndex(of: 0x0A) {
            let lineData = buffer[searchIndex..<newline]
            let text = String(decoding: lineData, as: UTF8.self)
            lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            searchIndex = buffer.index(after: newline)
        }
        scanOffset = buffer.distance(from: buffer.startIndex, to: searchIndex)
        if scanOffset > 64 * 1024 {
            buffer.removeSubrange(buffer.startIndex..<searchIndex)
            scanOffset = 0
        }
        lock.unlock()
        if let onLine {
            for line in lines where !line.isEmpty {
                onLine(line)
            }
        }
    }

    func finish() -> String {
        handle.readabilityHandler = nil
        let tail = handle.readDataToEndOfFile()
        if !tail.isEmpty {
            append(tail)
        }
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: allData, as: UTF8.self)
    }

    func cancel() {
        handle.readabilityHandler = nil
    }
}

private final class WorkItemBox: @unchecked Sendable {
    var item: DispatchWorkItem?
}

/// CheckedContinuation 的线程安全单次恢复门。
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<ProcessResult, Error>

    init(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<ProcessResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

/// 记录正在运行的子进程，应用退出时统一终止，避免留下孤儿 ffmpeg。
public final class RunningProcessRegistry: @unchecked Sendable {
    public static let shared = RunningProcessRegistry()

    private let lock = NSLock()
    private var processes: [Int32: Process] = [:]

    private init() {}

    func register(_ process: Process) {
        lock.lock()
        processes[process.processIdentifier] = process
        lock.unlock()
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: process.processIdentifier)
        lock.unlock()
    }

    public func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()
        for process in running where process.isRunning {
            process.terminate()
        }
    }
}

public enum ProcessRunner {
    /// 运行子进程，异步收集 stdout/stderr；通过 onStdoutLine 流式回调进度。
    /// - Parameter timeout: 可选的超时（秒）。超时/取消时先 SIGTERM，2 秒后仍未退出则 SIGKILL。
    public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        onStdoutLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = OutputCollector(handle: stdoutPipe.fileHandleForReading, onLine: onStdoutLine)
        let stderrCollector = OutputCollector(handle: stderrPipe.fileHandleForReading, onLine: nil)
        stdoutCollector.start()
        stderrCollector.start()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                let gate = ContinuationGate(continuation)
                let timeoutBox = WorkItemBox()

                process.terminationHandler = { finishedProcess in
                    timeoutBox.item?.cancel()
                    RunningProcessRegistry.shared.unregister(finishedProcess)
                    let out = stdoutCollector.finish()
                    let err = stderrCollector.finish()
                    gate.resume(.success(ProcessResult(status: finishedProcess.terminationStatus, stdout: out, stderr: err)))
                }

                if let timeout {
                    let item = DispatchWorkItem {
                        guard process.isRunning else { return }
                        Self.terminate(process)
                        gate.resume(.failure(ProcessRunnerError.timedOut(timeout)))
                    }
                    timeoutBox.item = item
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
                }

                do {
                    try process.run()
                    RunningProcessRegistry.shared.register(process)
                } catch {
                    timeoutBox.item?.cancel()
                    stdoutCollector.cancel()
                    stderrCollector.cancel()
                    gate.resume(.failure(error))
                }
            }
        } onCancel: {
            Self.terminate(process)
        }
    }

    /// 先发 SIGTERM；宽限 2 秒仍不退出则 SIGKILL，避免 ffmpeg 卡死时 App 永远等下去。
    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}
