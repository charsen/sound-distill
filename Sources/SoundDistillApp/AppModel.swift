import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SoundDistillCore

enum FFmpegStatus: Equatable {
    case checking
    case available(version: String)
    case missing

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Kind {
        case info
        case warning
        case error
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

extension Notification.Name {
    static let audioExtractOpenFiles = Notification.Name("SoundDistillOpenFiles")
}

struct BatchSummary: Identifiable {
    let id = UUID()
    let total: Int
    let completed: Int
    let failed: Int
    let skipped: Int
    let cancelled: Int
    let outputs: [URL]
    let outputBytes: Int64
    let elapsed: TimeInterval

    var hasIssues: Bool { failed > 0 || skipped > 0 || cancelled > 0 }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var jobs: [JobItem] = []
    @Published var isRunning = false
    @Published var ffmpegStatus: FFmpegStatus = .checking
    @Published var settings: AppSettings = SettingsStore.load() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var toast: ToastMessage?
    @Published var showHelp = false
    /// 汇总进度用 @Published 存储，否则子 JobItem 的 progress 变化不会通知到此视图。
    @Published var overallProgress: Double = 0
    /// 一批任务结束后的结果摘要。
    @Published var batchSummary: BatchSummary?

    private(set) var service: ConversionService?
    private var queueTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var openFilesObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var ffmpegTask: Task<Void, Never>?
    private var batchJobIDs: Set<UUID> = []
    private var batchTotal = 0
    private var batchStartedAt: Date?

    init() {
        restoreQueue()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistQueue()
            }
        }
        openFilesObserver = NotificationCenter.default.addObserver(
            forName: .audioExtractOpenFiles,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urls = notification.object as? [URL] else { return }
            Task { @MainActor [weak self] in
                self?.add(urls: urls)
            }
        }
        refreshFFmpeg()
        let pending = AppDelegate.pendingOpenURLs
        AppDelegate.pendingOpenURLs.removeAll()
        if !pending.isEmpty {
            add(urls: pending)
        }
    }

    deinit {
        if let openFilesObserver {
            NotificationCenter.default.removeObserver(openFilesObserver)
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: - 队列持久化

    private func restoreQueue() {
        let records = QueueStore.load()
        var seen = Set(jobs.map { $0.inputURL.standardizedFileURL.path })
        for record in records {
            let url = URL(fileURLWithPath: record.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { continue }
            let job = JobItem(inputURL: url, relativeDirectory: record.relativeDirectory)
            job.selectedAudioStreamIndex = record.audioStreamIndex
            jobs.append(job)
        }
        if !jobs.isEmpty {
            showToast("已恢复 \(jobs.count) 个待转换任务")
        }
    }

    private func persistQueue() {
        let records = jobs
            .filter { $0.status != .completed && $0.status != .skipped }
            .map {
                PersistedQueueJob(
                    path: $0.inputURL.path,
                    relativeDirectory: $0.relativeDirectory,
                    audioStreamIndex: $0.selectedAudioStreamIndex
                )
            }
        QueueStore.save(jobs: records)
    }

    // MARK: - ffmpeg

    func refreshFFmpeg() {
        ffmpegTask?.cancel()
        ffmpegStatus = .checking
        ffmpegTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tools = try FFmpegTools.locate()
                let version = await Self.ffmpegVersion(tools.ffmpegURL)
                guard !Task.isCancelled else { return }
                self.service = ConversionService(tools: tools)
                self.ffmpegStatus = .available(version: version)
                self.probePendingJobs()
            } catch {
                guard !Task.isCancelled else { return }
                self.service = nil
                self.ffmpegStatus = .missing
            }
        }
    }

    private static func ffmpegVersion(_ executable: URL) async -> String {
        guard let result = try? await ProcessRunner.run(executable: executable, arguments: ["-version"]),
              result.succeeded else {
            return "未知版本"
        }
        let firstLine = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        let prefix = "ffmpeg version "
        if firstLine.hasPrefix(prefix) {
            return firstLine.dropFirst(prefix.count).split(separator: " ").first.map(String.init) ?? "未知版本"
        }
        return firstLine.isEmpty ? "未知版本" : firstLine
    }

    func copyFFmpegInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
        showToast("已复制安装命令，请在终端执行")
    }

    // MARK: - 文件

    func addFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择视频文件"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let types = MediaTypes.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = types.isEmpty ? [.movie] : types
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择包含视频的文件夹"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func add(urls: [URL]) {
        let candidates = mediaCandidates(from: urls)
        guard !candidates.isEmpty else {
            if !urls.isEmpty {
                showToast("没有找到支持的视频文件", kind: .warning)
            }
            return
        }
        var existing = Set(jobs.map { $0.inputURL.standardizedFileURL.resolvingSymlinksInPath().path })
        var added = 0
        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.resolvingSymlinksInPath().path
            guard existing.insert(path).inserted else { continue }
            jobs.append(JobItem(inputURL: candidate.url, relativeDirectory: candidate.relativeDirectory))
            added += 1
        }
        if added > 0 {
            showToast(isRunning ? "已加入队列，将在下一批处理" : "已添加 \(added) 个视频")
            persistQueue()
            probePendingJobs()
        } else {
            showToast("这些文件已经在队列中", kind: .warning)
        }
    }

    /// 展开文件/文件夹，并记录文件夹导入时的相对子目录。
    private func mediaCandidates(from urls: [URL]) -> [(url: URL, relativeDirectory: String?)] {
        let fileManager = FileManager.default
        var result: [(URL, String?)] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let root = url.standardizedFileURL
                for file in MediaTypes.collectMediaFiles(from: [url]) {
                    let filePath = file.standardizedFileURL.path
                    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                    var relative: String?
                    if filePath.hasPrefix(rootPrefix) {
                        let inside = String(filePath.dropFirst(rootPrefix.count))
                        let parent = (inside as NSString).deletingLastPathComponent
                        if !parent.isEmpty, parent != "." { relative = parent }
                    }
                    result.append((file, relative))
                }
            } else if MediaTypes.isSupported(url) {
                result.append((url, nil))
            }
        }
        return result
    }

    private func probePendingJobs() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.probeTask = nil
                // 在探测任务结束前又加入了新文件时，补一次调度。
                if self.service != nil,
                   self.jobs.contains(where: { $0.info == nil && !$0.probeFailed && $0.status == .queued }) {
                    self.probePendingJobs()
                }
            }
            while !Task.isCancelled {
                guard let job = self.jobs.first(where: { $0.info == nil && !$0.probeFailed && $0.status == .queued }) else {
                    break
                }
                guard let service = self.service else { break }
                job.isProbingDetails = true
                do {
                    job.info = try await service.probeVideo(job.inputURL)
                    job.isProbingDetails = false
                } catch SoundDistillError.cancelled {
                    job.isProbingDetails = false
                    job.status = .cancelled
                    job.stageText = "已取消"
                } catch is CancellationError {
                    job.isProbingDetails = false
                    job.status = .cancelled
                    job.stageText = "已取消"
                } catch {
                    job.isProbingDetails = false
                    job.probeFailed = true
                    job.status = .failed
                    job.stageText = "读取视频信息失败"
                    job.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 队列操作

    func remove(_ job: JobItem) {
        // 批量运行时暂不允许删除，避免从列表消失后仍被队列继续处理。
        guard !isRunning, !job.status.isActive, !job.isProbingDetails else { return }
        jobs.removeAll { $0.id == job.id }
        persistQueue()
    }

    func removeAll() {
        guard !isRunning else { return }
        jobs.removeAll()
        persistQueue()
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.status.isFinished }
        persistQueue()
    }

    func selectAudioStream(_ index: Int?, for job: JobItem) {
        guard !isRunning else { return }
        job.selectedAudioStreamIndex = index
        if job.status == .failed || job.status == .cancelled {
            job.status = .queued
            job.stageText = "等待处理"
            job.errorMessage = nil
        }
    }

    func retry(_ job: JobItem) {
        guard !isRunning else { return }
        reset(job)
        startConversion(only: job)
    }

    private func reset(_ job: JobItem) {
        job.status = .queued
        job.progress = 0
        job.stageText = "等待处理"
        job.result = nil
        job.errorMessage = nil
        job.probeFailed = false
        job.warningText = nil
    }

    var queuedCount: Int { jobs.filter { $0.status == .queued }.count }
    var completedCount: Int { jobs.filter { $0.status == .completed }.count }
    var failedCount: Int { jobs.filter { $0.status == .failed }.count }
    var activeCount: Int { jobs.filter { $0.status.isActive }.count }

    var canStart: Bool {
        !isRunning && service != nil && jobs.contains { $0.status == .queued || $0.status == .failed || $0.status == .cancelled }
    }

    var startButtonTitle: String {
        if isRunning { return "转换中…" }
        if queuedCount > 0 { return "开始转换" }
        if failedCount > 0 { return "重试失败项" }
        if jobs.contains(where: { $0.status == .cancelled }) { return "重新开始" }
        if completedCount > 0 { return "全部完成" }
        return "开始转换"
    }

    private func updateOverallProgress() {
        guard batchTotal > 0 else {
            overallProgress = 0
            return
        }
        let batchJobs = jobs.filter { batchJobIDs.contains($0.id) }
        let finished = batchJobs.filter { $0.status.isFinished }.count
        let activeFraction = batchJobs.filter { $0.status.isActive }.reduce(0) { $0 + $1.progress }
        overallProgress = min(1, (Double(finished) + activeFraction) / Double(batchTotal))
    }

    // MARK: - 转换

    func startConversion(only singleJob: JobItem? = nil) {
        guard !isRunning else { return }
        guard service != nil else {
            showToast("ffmpeg 不可用，请先安装或点击重新检测", kind: .error)
            return
        }
        let targets: [JobItem]
        if let singleJob {
            targets = [singleJob]
        } else {
            targets = jobs.filter { $0.status == .queued || $0.status == .failed || $0.status == .cancelled }
        }
        guard !targets.isEmpty else { return }
        for job in targets { reset(job) }
        batchJobIDs = Set(targets.map(\.id))
        batchTotal = targets.count
        batchStartedAt = Date()
        overallProgress = 0
        persistQueue()
        objectWillChange.send()

        // 一批任务使用同一份设置快照，避免转换途中修改音质/输出目录导致同批结果不一致。
        let batchSettings = settings.conversionSettings
        let concurrency = max(1, min(settings.concurrency, 8))
        let preserveFolderStructure = settings.preserveFolderStructure
        isRunning = true
        queueTask = Task { [weak self] in
            await self?.runQueue(
                settings: batchSettings,
                concurrency: concurrency,
                preserveFolderStructure: preserveFolderStructure
            )
        }
    }

    private func runQueue(
        settings batchSettings: ConversionSettings,
        concurrency: Int,
        preserveFolderStructure: Bool
    ) async {
        guard let service else {
            isRunning = false
            return
        }
        let pending = jobs.filter { $0.status == .queued && batchJobIDs.contains($0.id) }
        var nextIndex = 0
        let limit = concurrency

        await withTaskGroup(of: Void.self) { group in
            let initial = min(limit, pending.count)
            for _ in 0..<initial {
                let job = pending[nextIndex]
                nextIndex += 1
                group.addTask { [weak self] in
                    await self?.run(
                        job,
                        service: service,
                        settings: batchSettings,
                        preserveFolderStructure: preserveFolderStructure
                    )
                }
            }
            for await _ in group {
                if nextIndex < pending.count {
                    let job = pending[nextIndex]
                    nextIndex += 1
                    group.addTask { [weak self] in
                        await self?.run(
                            job,
                            service: service,
                            settings: batchSettings,
                            preserveFolderStructure: preserveFolderStructure
                        )
                    }
                }
            }
        }

        isRunning = false
        queueTask = nil
        updateOverallProgress()
        batchSummary = makeBatchSummary()
        batchStartedAt = nil
        persistQueue()
        if completedCount > 0 {
            if settings.playSoundOnFinish {
                NSSound(named: "Glass")?.play()
            }
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    private func makeBatchSummary() -> BatchSummary {
        let batchJobs = jobs.filter { batchJobIDs.contains($0.id) }
        let outputs = batchJobs.compactMap { $0.result?.outputURL }
        let bytes = batchJobs.reduce(Int64(0)) { $0 + ($1.result?.outputFileSize ?? 0) }
        return BatchSummary(
            total: batchJobs.count,
            completed: batchJobs.filter { $0.status == .completed }.count,
            failed: batchJobs.filter { $0.status == .failed }.count,
            skipped: batchJobs.filter { $0.status == .skipped }.count,
            cancelled: batchJobs.filter { $0.status == .cancelled }.count,
            outputs: outputs,
            outputBytes: bytes,
            elapsed: batchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        )
    }

    private func run(
        _ job: JobItem,
        service: ConversionService,
        settings: ConversionSettings,
        preserveFolderStructure: Bool
    ) async {
        job.status = .probing
        job.stageText = "读取视频信息"
        job.progress = 0
        var jobSettings = settings
        jobSettings.audioStreamIndex = job.selectedAudioStreamIndex
        if preserveFolderStructure, jobSettings.outputDirectory != nil {
            jobSettings.outputSubdirectory = job.relativeDirectory
        }
        do {
            let result = try await service.convert(
                input: job.inputURL,
                settings: jobSettings,
                onProgress: { [weak self, weak job] progress in
                    Task { @MainActor [weak self, weak job] in
                        guard let self, let job else { return }
                        // 完成/取消后可能还有排队的进度回调，不能把终态改回“转换中”。
                        guard job.status == .probing || job.status == .converting else { return }
                        job.progress = max(job.progress, progress.fraction)
                        job.stageText = progress.stage.displayName + " " + "\(Int(progress.fraction * 100))%"
                        if progress.stage == .encoding {
                            job.status = .converting
                        }
                        self.updateOverallProgress()
                    }
                }
            )
            job.result = result
            job.progress = 1
            job.status = .completed
            job.stageText = result.coverOrigin == .none ? "已完成（无封面）" : result.coverOrigin.displayName
            job.errorMessage = nil
            job.warningText = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "；")
        } catch SoundDistillError.outputExists {
            job.status = .skipped
            job.stageText = "同名文件已存在"
        } catch SoundDistillError.cancelled {
            job.status = .cancelled
            job.stageText = "已取消"
        } catch is CancellationError {
            job.status = .cancelled
            job.stageText = "已取消"
        } catch {
            job.status = .failed
            job.stageText = "转换失败"
            job.errorMessage = error.localizedDescription
            job.warningText = nil
        }
        updateOverallProgress()
        objectWillChange.send()
        persistQueue()
    }

    func cancelAll() {
        guard isRunning else { return }
        probeTask?.cancel()
        queueTask?.cancel()
        for job in jobs where job.status == .queued {
            job.status = .cancelled
            job.stageText = "已取消"
        }
        updateOverallProgress()
        objectWillChange.send()
        persistQueue()
        showToast("正在取消任务…", kind: .warning)
    }

    // MARK: - 输出

    /// 打开开关时调用：只有用户真正选好目录才把开关置为开启；取消则保持关闭。
    func enableCustomOutput() {
        if !settings.customOutputPath.isEmpty {
            settings.useCustomOutput = true
            return
        }
        chooseOutputFolder()
        if settings.customOutputPath.isEmpty {
            settings.useCustomOutput = false
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !settings.customOutputPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.customOutputPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.customOutputPath = url.path
            settings.useCustomOutput = true
        }
    }

    func reveal(_ job: JobItem) {
        guard let output = job.result?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    func openOutputFolder() {
        if settings.useCustomOutput, !settings.customOutputPath.isEmpty,
           FileManager.default.fileExists(atPath: settings.customOutputPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: settings.customOutputPath, isDirectory: true))
            return
        }
        if let output = jobs.compactMap({ $0.result?.outputURL }).first {
            NSWorkspace.shared.activateFileViewerSelecting([output])
            return
        }
        showToast("还没有生成输出文件", kind: .warning)
    }

    // MARK: - 提示

    func showToast(_ text: String, kind: ToastMessage.Kind = .info) {
        let message = ToastMessage(text: text, kind: kind)
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }
}
