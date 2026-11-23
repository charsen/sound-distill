import Foundation

struct PersistedQueueJob: Codable {
    let path: String
    let relativeDirectory: String?
    let audioStreamIndex: Int?

    init(path: String, relativeDirectory: String? = nil, audioStreamIndex: Int? = nil) {
        self.path = path
        self.relativeDirectory = relativeDirectory
        self.audioStreamIndex = audioStreamIndex
    }
}

/// 持久化未完成的任务，App 退出后下次启动可以恢复队列。
enum QueueStore {
    private static let fileURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SoundDistill", isDirectory: true)
        return directory.appendingPathComponent("queue.json")
    }()

    static func load() -> [PersistedQueueJob] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let records = try? JSONDecoder().decode([PersistedQueueJob].self, from: data) {
            return records
        }
        // 兼容旧版本的 [String] 队列文件。
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths.map { PersistedQueueJob(path: $0) }
        }
        return []
    }

    static func save(jobs: [PersistedQueueJob]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(jobs)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // 队列持久化失败不应阻断转换主流程。
        }
    }
}
