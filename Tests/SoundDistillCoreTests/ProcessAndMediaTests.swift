import XCTest
@testable import SoundDistillCore

final class ProcessRunnerTests: XCTestCase {
    func testTimeoutKillsStubbornProcess() async throws {
        let started = Date()
        do {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; sleep 30"],
                timeout: 0.4
            )
            XCTFail("应因超时失败")
        } catch ProcessRunnerError.timedOut(_) {
            XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        }
    }

    func testCancellationTerminatesChildProcess() async throws {
        let task = Task {
            try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        let started = Date()
        task.cancel()
        let result = try await task.value
        XCTAssertNotEqual(result.status, 0, "被取消的进程应以非零状态退出")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "取消应尽快生效")
    }
}

final class MediaTypesTests: XCTestCase {
    func testCollectMediaFilesScansRecursivelyAndDeduplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("子目录", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: root.appendingPathComponent("a.mp4").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("b.MKV").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("c.txt").path, contents: Data())

        let files = MediaTypes.collectMediaFiles(from: [root, root.appendingPathComponent("a.mp4")])
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(files.map { $0.lastPathComponent }), ["a.mp4", "b.MKV"])
    }
}
