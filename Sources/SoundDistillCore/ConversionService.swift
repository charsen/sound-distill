import Foundation

/// 为并发转换原子地分配输出路径，避免两个同名视频同时转换时抢同一个文件名。
public final class OutputPathReservoir: @unchecked Sendable {
    private let lock = NSLock()
    private var reserved: Set<String> = []

    public init() {}

    public func reserve(input: URL, settings: ConversionSettings) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let url = try OutputPathResolver.resolve(input: input, settings: settings) { path in
            FileManager.default.fileExists(atPath: path) || reserved.contains(path.lowercased())
        }
        // overwrite 可能绕过 fileExists 检查，必须显式拒绝同一进程内的并发同名写。
        if settings.conflictPolicy == .overwrite, reserved.contains(url.path.lowercased()) {
            throw SoundDistillError.outputInUse(url)
        }
        reserved.insert(url.path.lowercased())
        return url
    }

    public func release(_ url: URL) {
        lock.lock()
        reserved.remove(url.path.lowercased())
        lock.unlock()
    }
}

/// 单个视频 -> MP3 的完整流程：探测、封面、转码、校验。
public final class ConversionService: @unchecked Sendable {
    public let tools: FFmpegTools
    private let probe: MediaProbe
    private let outputReservoir = OutputPathReservoir()

    public init(tools: FFmpegTools) {
        self.tools = tools
        self.probe = MediaProbe(tools: tools)
    }

    public func probeVideo(_ url: URL) async throws -> VideoInfo {
        try await probe.probe(url)
    }

    public func convert(
        input: URL,
        settings: ConversionSettings,
        onProgress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> ConversionResult {
        try Task.checkCancellation()
        guard FileManager.default.isReadableFile(atPath: input.path) else {
            throw SoundDistillError.probeFailed("文件不存在或不可读：\(input.lastPathComponent)")
        }

        // 先按冲突策略确定输出路径：skip 可以在读取损坏文件前直接跳过。
        let outputURL = try outputReservoir.reserve(input: input, settings: settings)
        defer { outputReservoir.release(outputURL) }

        onProgress(ConversionProgress(stage: .probing, fraction: 0.01))
        let info = try await probe.probe(input)
        try Task.checkCancellation()

        let selectedAudio = settings.audioStreamIndex.flatMap { index in
            info.audioStreams.first(where: { $0.index == index })
        } ?? info.primaryAudioStream
        let effectiveAudioBitrate = settings.quality.effectiveCBRBitrate(forSampleRate: selectedAudio?.sampleRate ?? 0)
        var qualityWarnings: [String] = []
        if let requested = settings.quality.requestedCBRBitrate,
           let effective = effectiveAudioBitrate,
           effective < requested,
           let sampleRate = selectedAudio?.sampleRate {
            qualityWarnings.append("源音轨 \(sampleRate) Hz，MP3 最高 \(effective) kbps；已自动按 \(effective) kbps 编码")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 全部编码先写入同目录临时文件，成功校验后才原子替换最终文件；失败绝不碰已存在的原文件。
        let tempOutputURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".sounddistill-\(UUID().uuidString).mp3")
        defer { try? fileManager.removeItem(at: tempOutputURL) }

        // 每次转换使用独立临时目录，结束后整体清理。
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SoundDistill", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        onProgress(ConversionProgress(stage: .preparingCover, fraction: 0.04))
        let cover = await prepareCover(info: info, policy: settings.coverPolicy, tempDirectory: tempDirectory)
        try Task.checkCancellation()

        onProgress(ConversionProgress(stage: .encoding, fraction: 0.08))
        let arguments = FFmpegCommandBuilder.encodingArguments(
            input: input,
            output: tempOutputURL,
            info: info,
            coverURL: cover.url,
            settings: settings
        )

        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                executable: tools.ffmpegURL,
                arguments: arguments,
                timeout: max(60, info.duration * 4),
                onStdoutLine: { line in
                    guard let fraction = Self.progressFraction(from: line, duration: info.duration) else { return }
                    onProgress(ConversionProgress(stage: .encoding, fraction: 0.08 + fraction * 0.92))
                }
            )
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw SoundDistillError.cancelled
            }
            throw SoundDistillError.encodingFailed(error.localizedDescription)
        }

        if Task.isCancelled {
            throw SoundDistillError.cancelled
        }

        guard result.succeeded else {
            throw SoundDistillError.encodingFailed(Self.shortError(result.stderr))
        }

        let fileSize = (try? fileManager.attributesOfItem(atPath: tempOutputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 1024 else {
            throw SoundDistillError.invalidOutput("输出文件为空或过小")
        }

        if Task.isCancelled {
            throw SoundDistillError.cancelled
        }
        guard try await isValidMP3(tempOutputURL) else {
            if Task.isCancelled { throw SoundDistillError.cancelled }
            throw SoundDistillError.invalidOutput("ffprobe 未检测到有效 MP3 音轨")
        }

        let actualOutputURL = try commitOutput(from: tempOutputURL, to: outputURL, policy: settings.conflictPolicy)
        onProgress(ConversionProgress(stage: .encoding, fraction: 1))
        return ConversionResult(
            outputURL: actualOutputURL,
            sourceDuration: info.duration,
            outputFileSize: fileSize,
            coverOrigin: cover.origin,
            warnings: qualityWarnings + cover.warnings,
            effectiveAudioBitrate: effectiveAudioBitrate,
            sourceAudioSampleRate: selectedAudio?.sampleRate
        )
    }

    /// 成功校验后把临时文件提交到最终路径。overwrite 用原子替换，失败只留临时文件。
    private func commitOutput(from temp: URL, to final: URL, policy: ConflictPolicy) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: final.path, isDirectory: &isDirectory)

        if exists {
            if isDirectory.boolValue {
                throw SoundDistillError.invalidOutput("输出路径是文件夹，未覆盖：\(final.lastPathComponent)")
            }
            switch policy {
            case .skip:
                throw SoundDistillError.outputExists(final)
            case .overwrite:
                _ = try fileManager.replaceItemAt(final, withItemAt: temp, backupItemName: nil, options: [])
                return final
            case .rename:
                let alternative = try uniqueSibling(of: final)
                try fileManager.moveItem(at: temp, to: alternative)
                return alternative
            }
        }

        try fileManager.moveItem(at: temp, to: final)
        return final
    }

    private func uniqueSibling(of url: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(base) (\(counter))")
                .appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - 封面

    private struct PreparedCover {
        let url: URL?
        let origin: CoverOrigin
        let warnings: [String]
    }

    private func prepareCover(info: VideoInfo, policy: CoverPolicy, tempDirectory: URL) async -> PreparedCover {
        var warnings: [String] = []

        if policy == .none {
            return PreparedCover(url: nil, origin: .none, warnings: [])
        }

        if policy == .smart {
            if let candidate = info.coverCandidates.first {
                let destination = tempDirectory.appendingPathComponent("cover_embedded.jpg")
                if await extractCover(candidate: candidate, input: info.url, destination: destination) {
                    return PreparedCover(url: destination, origin: .embedded, warnings: [])
                }
                warnings.append("内嵌封面读取失败，已改用视频画面")
            }
        }

        // 第 1 秒优先，失败取第 2 秒；极短视频再退回第 0 秒。
        for seconds in [1.0, 2.0, 0.0] {
            if info.duration > 0, seconds > info.duration + 0.05 {
                continue
            }
            let destination = tempDirectory.appendingPathComponent(String(format: "cover_frame_%.0f.jpg", locale: Locale(identifier: "en_US_POSIX"), seconds))
            if await extractFrame(input: info.url, seconds: seconds, destination: destination) {
                return PreparedCover(url: destination, origin: .frame(seconds: seconds), warnings: warnings)
            }
        }

        warnings.append("无法从视频提取封面，已生成无封面 MP3")
        return PreparedCover(url: nil, origin: .none, warnings: warnings)
    }

    private func extractCover(candidate: CoverCandidate, input: URL, destination: URL) async -> Bool {
        let arguments = FFmpegCommandBuilder.coverExtractionArguments(input: input, candidate: candidate, destination: destination)
        return await runSilently(arguments: arguments, output: destination)
    }

    private func extractFrame(input: URL, seconds: Double, destination: URL) async -> Bool {
        let arguments = FFmpegCommandBuilder.frameExtractionArguments(input: input, at: seconds, destination: destination)
        return await runSilently(arguments: arguments, output: destination)
    }

    private func runSilently(arguments: [String], output: URL) async -> Bool {
        guard let result = try? await ProcessRunner.run(executable: tools.ffmpegURL, arguments: arguments, timeout: 30) else {
            return false
        }
        guard result.succeeded else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 512
    }

    // MARK: - 校验与进度

    private func isValidMP3(_ url: URL) async throws -> Bool {
        let arguments = [
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=codec_name",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]
        guard let result = try? await ProcessRunner.run(executable: tools.ffprobeURL, arguments: arguments) else {
            return false
        }
        return result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "mp3"
    }

    static func progressFraction(from line: String, duration: Double) -> Double? {
        guard duration > 0 else { return nil }
        guard line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return nil }
        guard let valueText = line.split(separator: "=", maxSplits: 1).last,
              let microseconds = Double(valueText), microseconds >= 0 else {
            return nil
        }
        return min(microseconds / 1_000_000 / duration, 0.999)
    }

    private static func shortError(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "ffmpeg 返回未知错误" }
        if trimmed.count <= 800 { return trimmed }
        return String(trimmed.suffix(800))
    }
}
