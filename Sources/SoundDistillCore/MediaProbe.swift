import Foundation

/// 用 ffprobe 读取视频容器信息。
public final class MediaProbe: @unchecked Sendable {
    private let tools: FFmpegTools

    public init(tools: FFmpegTools) {
        self.tools = tools
    }

    public func probe(_ url: URL) async throws -> VideoInfo {
        let arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(executable: tools.ffprobeURL, arguments: arguments, timeout: 30)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw SoundDistillError.cancelled
            }
            throw SoundDistillError.probeFailed(error.localizedDescription)
        }

        if Task.isCancelled {
            throw SoundDistillError.cancelled
        }
        guard result.succeeded else {
            if Task.isCancelled { throw SoundDistillError.cancelled }
            throw SoundDistillError.probeFailed(Self.shortError(result.stderr))
        }
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SoundDistillError.probeFailed("无法解析 ffprobe 输出")
        }
        return try Self.parse(root: root, url: url)
    }

    // MARK: - 解析

    static func parse(root: [String: Any], url: URL) throws -> VideoInfo {
        let format = root["format"] as? [String: Any] ?? [:]
        let rawStreams = root["streams"] as? [[String: Any]] ?? []
        let formatTags = normalizedTags(format["tags"])

        var audioStreams: [AudioStreamInfo] = []
        var coverCandidates: [CoverCandidate] = []
        var videoWidth: Int?
        var videoHeight: Int?
        var frameRate: Double?
        var maxStreamDuration: Double = 0

        for (position, stream) in rawStreams.enumerated() {
            let index = intValue(stream["index"]) ?? position
            let codecType = stringValue(stream["codec_type"]) ?? ""
            let codecName = stringValue(stream["codec_name"]) ?? "unknown"
            let tags = normalizedTags(stream["tags"])
            let disposition = stream["disposition"] as? [String: Any] ?? [:]

            if let duration = parseDuration(stream["duration"]) {
                maxStreamDuration = max(maxStreamDuration, duration)
            } else if let durationText = tags["duration"], let duration = parseDuration(durationText) {
                maxStreamDuration = max(maxStreamDuration, duration)
            }

            switch codecType {
            case "audio":
                audioStreams.append(AudioStreamInfo(
                    index: index,
                    codecName: codecName,
                    channels: intValue(stream["channels"]) ?? 2,
                    sampleRate: intValue(stream["sample_rate"]) ?? 44100,
                    bitRate: intValue(stream["bit_rate"]),
                    language: tags["language"],
                    title: tags["title"],
                    isDefault: intValue(disposition["default"]) == 1
                ))
            case "video":
                let isAttachedPic = intValue(disposition["attached_pic"]) == 1
                if isAttachedPic {
                    coverCandidates.append(CoverCandidate(
                        streamIndex: index,
                        kind: .attachedPicture,
                        codecName: codecName,
                        mimeType: tags["mimetype"],
                        width: intValue(stream["width"]),
                        height: intValue(stream["height"]),
                        filename: tags["filename"]
                    ))
                } else if videoWidth == nil {
                    videoWidth = intValue(stream["width"])
                    videoHeight = intValue(stream["height"])
                    if let rate = stringValue(stream["avg_frame_rate"]) {
                        frameRate = parseFrameRate(rate)
                    }
                }
            case "attachment":
                if let mime = tags["mimetype"], mime.lowercased().hasPrefix("image/") {
                    coverCandidates.append(CoverCandidate(
                        streamIndex: index,
                        kind: .attachment,
                        codecName: codecName,
                        mimeType: mime,
                        width: intValue(stream["width"]),
                        height: intValue(stream["height"]),
                        filename: tags["filename"]
                    ))
                }
            default:
                break
            }
        }

        // 内嵌封面优先；同类型按流顺序。
        coverCandidates.sort { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .attachedPicture
            }
            return lhs.streamIndex < rhs.streamIndex
        }

        guard !audioStreams.isEmpty else {
            throw SoundDistillError.noAudioTrack
        }

        let parsedFormatDuration = parseDuration(format["duration"])
        let duration: Double
        if let parsedFormatDuration, parsedFormatDuration.isFinite, parsedFormatDuration > 0 {
            duration = parsedFormatDuration
        } else {
            duration = maxStreamDuration
        }
        let fileSize = int64Value(format["size"]) ?? fileSizeOnDisk(url)

        return VideoInfo(
            url: url,
            duration: duration,
            formatName: stringValue(format["format_name"]) ?? "unknown",
            fileSize: fileSize,
            audioStreams: audioStreams,
            coverCandidates: coverCandidates,
            metadata: formatTags,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            frameRate: frameRate
        )
    }

    // MARK: - 字段工具

    private static func normalizedTags(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dictionary {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let text = stringValue(raw) {
                result[normalizedKey] = text
            }
        }
        return result
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let text as String:
            return Int64(text)
        default:
            return nil
        }
    }

    static func parseDuration(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        guard let text = stringValue(value) else { return nil }
        if let seconds = Double(text) {
            return seconds
        }
        // Matroska 的 DURATION 标签是 HH:MM:SS.nnnnnnnnn
        let parts = text.split(separator: ":")
        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        return nil
    }

    static func parseFrameRate(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }
        return Double(text)
    }

    private static func fileSizeOnDisk(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func shortError(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 600 { return trimmed }
        return String(trimmed.suffix(600))
    }
}
