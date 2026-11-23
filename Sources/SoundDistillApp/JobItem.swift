import SwiftUI
import SoundDistillCore

enum JobStatus: Equatable {
    case queued
    case probing
    case converting
    case completed
    case failed
    case cancelled
    case skipped

    var isActive: Bool {
        self == .probing || self == .converting
    }

    var isFinished: Bool {
        self == .completed || self == .failed || self == .cancelled || self == .skipped
    }

    var title: String {
        switch self {
        case .queued:     return "等待中"
        case .probing:    return "读取信息"
        case .converting: return "转换中"
        case .completed:  return "已完成"
        case .failed:     return "失败"
        case .cancelled:  return "已取消"
        case .skipped:    return "已跳过"
        }
    }

    var iconName: String {
        switch self {
        case .queued:     return "clock"
        case .probing:    return "magnifyingglass"
        case .converting: return "waveform"
        case .completed:  return "checkmark"
        case .failed:     return "exclamationmark"
        case .cancelled:  return "xmark"
        case .skipped:    return "arrow.right.to.line"
        }
    }

    var tint: Color {
        switch self {
        case .queued:     return Theme.textSecondary
        case .probing:    return Theme.brandPrimary
        case .converting: return Theme.brandPrimary
        case .completed:  return Theme.success
        case .failed:     return Theme.danger
        case .cancelled:  return Theme.textSecondary
        case .skipped:    return Theme.warning
        }
    }
}

@MainActor
final class JobItem: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    /// 从文件夹导入时保存相对子目录，用于“保持原目录结构”。
    let relativeDirectory: String?

    @Published var status: JobStatus = .queued
    @Published var progress: Double = 0
    @Published var stageText = "等待处理"
    @Published var info: VideoInfo?
    @Published var result: ConversionResult?
    @Published var errorMessage: String?
    @Published var probeFailed = false
    /// 后台 ffprobe 读取期间为 true；状态仍是 queued，避免与批量任务的状态竞争。
    @Published var isProbingDetails = false
    /// 用户手动选择的音轨绝对 index；nil 表示跟随容器默认音轨。
    @Published var selectedAudioStreamIndex: Int?
    /// 转换完成后展示的码率/封面等业务提示。
    @Published var warningText: String?

    init(inputURL: URL, relativeDirectory: String? = nil) {
        self.inputURL = inputURL
        self.relativeDirectory = relativeDirectory
    }

    var audioStreams: [AudioStreamInfo] { info?.audioStreams ?? [] }

    var selectedAudioStream: AudioStreamInfo? {
        if let selectedAudioStreamIndex,
           let stream = audioStreams.first(where: { $0.index == selectedAudioStreamIndex }) {
            return stream
        }
        return info?.primaryAudioStream
    }

    var audioTrackLabel: String {
        guard let stream = selectedAudioStream else { return "默认音轨" }
        return stream.displayLabel
    }

    var hasMultipleAudioTracks: Bool { audioStreams.count > 1 }

    var displayName: String {
        inputURL.lastPathComponent
    }

    var fileExtension: String {
        inputURL.pathExtension.uppercased()
    }

    var inputFileSize: Int64 {
        if let info { return info.fileSize }
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    var subtitle: String {
        var parts: [String] = []
        if let info {
            parts.append(info.displayDuration)
            if let resolution = info.resolutionDescription { parts.append(resolution) }
            parts.append(Self.formatBytes(info.fileSize))
            if info.audioStreams.count > 1 {
                parts.append("\(info.audioStreams.count) 音轨")
            }
            if info.hasEmbeddedCover {
                parts.append("含封面")
            }
        } else {
            parts.append(fileExtension)
            parts.append(Self.formatBytes(inputFileSize))
        }
        return parts.joined(separator: " · ")
    }

    var completionSubtitle: String? {
        guard let result else { return nil }
        var parts: [String] = [Self.formatBytes(result.outputFileSize)]
        if let bitrate = result.effectiveAudioBitrate {
            parts.append("\(bitrate) kbps")
        }
        if result.coverOrigin != .none {
            parts.append(result.coverOrigin.displayName)
        }
        return parts.joined(separator: " · ")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
