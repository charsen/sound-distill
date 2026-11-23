import Foundation

// MARK: - 视频信息

public struct AudioStreamInfo: Sendable, Equatable {
    public let index: Int
    public let codecName: String
    public let channels: Int
    public let sampleRate: Int
    public let bitRate: Int?
    public let language: String?
    public let title: String?
    /// 容器的 disposition.default 标记，多音轨时用于挑选主音轨。
    public let isDefault: Bool

    public init(index: Int, codecName: String, channels: Int, sampleRate: Int, bitRate: Int?, language: String?, title: String?, isDefault: Bool = false) {
        self.index = index
        self.codecName = codecName
        self.channels = channels
        self.sampleRate = sampleRate
        self.bitRate = bitRate
        self.language = language
        self.title = title
        self.isDefault = isDefault
    }

    public var channelDescription: String {
        switch channels {
        case 1: return "单声道"
        case 2: return "立体声"
        default: return "\(channels) 声道"
        }
    }

    /// 音轨在菜单中的可读名称，优先用容器标题，其次语言。
    public var displayLabel: String {
        let name: String
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = title
        } else if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, language != "und" {
            name = language
        } else {
            name = "音轨 \(index + 1)"
        }
        var details: [String] = [name, codecName.uppercased(), channelDescription]
        if isDefault { details.append("默认") }
        return details.joined(separator: " · ")
    }
}

public enum CoverCandidateKind: Sendable, Equatable {
    /// MP4/MOV 等容器中的 attached_pic 视频流（通常是 covr atom）。
    case attachedPicture
    /// MKV 等容器中的附件流（codec_type=attachment，mimetype 为 image/*）。
    case attachment
}

public struct CoverCandidate: Sendable, Equatable {
    /// ffprobe 里的全局 stream index。
    public let streamIndex: Int
    public let kind: CoverCandidateKind
    public let codecName: String
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let filename: String?

    public init(streamIndex: Int, kind: CoverCandidateKind, codecName: String, mimeType: String?, width: Int?, height: Int?, filename: String?) {
        self.streamIndex = streamIndex
        self.kind = kind
        self.codecName = codecName
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.filename = filename
    }

    public var displayDescription: String {
        var parts: [String] = [kind == .attachedPicture ? "内嵌封面" : "封面附件"]
        if let width, let height { parts.append("\(width)×\(height)") }
        if let mimeType { parts.append(mimeType) }
        return parts.joined(separator: " · ")
    }
}

public struct VideoInfo: Sendable, Equatable {
    public let url: URL
    public let duration: Double
    public let formatName: String
    public let fileSize: Int64
    public let audioStreams: [AudioStreamInfo]
    public let coverCandidates: [CoverCandidate]
    public let metadata: [String: String]
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let frameRate: Double?

    public init(
        url: URL,
        duration: Double,
        formatName: String,
        fileSize: Int64,
        audioStreams: [AudioStreamInfo],
        coverCandidates: [CoverCandidate],
        metadata: [String: String],
        videoWidth: Int?,
        videoHeight: Int?,
        frameRate: Double?
    ) {
        self.url = url
        self.duration = duration
        self.formatName = formatName
        self.fileSize = fileSize
        self.audioStreams = audioStreams
        self.coverCandidates = coverCandidates
        self.metadata = metadata
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.frameRate = frameRate
    }

    public var primaryAudioStream: AudioStreamInfo? {
        audioStreams.first(where: { $0.isDefault }) ?? audioStreams.first
    }

    public var hasEmbeddedCover: Bool { !coverCandidates.isEmpty }

    public var displayDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var resolutionDescription: String? {
        guard let videoWidth, let videoHeight else { return nil }
        return "\(videoWidth)×\(videoHeight)"
    }
}
