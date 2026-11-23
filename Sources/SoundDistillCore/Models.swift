import Foundation

// MARK: - 音质档位

/// MP3 编码档位。默认 320 kbps CBR：兼容性最好，也是 MP3 格式的码率上限。
/// VBR V0 在同等听感下体积更小，但部分老设备显示时长可能不精确。
public enum MP3Quality: String, CaseIterable, Codable, Sendable, Identifiable {
    case cbr320
    case vbrV0
    case cbr256
    case cbr192

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cbr320: return "极致 · 320 kbps"
        case .vbrV0:  return "极致 · VBR V0"
        case .cbr256: return "高质 · 256 kbps"
        case .cbr192: return "标准 · 192 kbps"
        }
    }

    public var shortName: String {
        switch self {
        case .cbr320: return "320k"
        case .vbrV0:  return "V0"
        case .cbr256: return "256k"
        case .cbr192: return "192k"
        }
    }

    public var detail: String {
        switch self {
        case .cbr320: return "固定码率，MP3 最高规格，任何设备都能稳定播放。"
        case .vbrV0:  return "可变码率，同等体积下听感最佳，适合收藏。"
        case .cbr256: return "固定码率，体积与音质平衡。"
        case .cbr192: return "固定码率，体积更小，适合日常收听。"
        }
    }

    /// libmp3lame 参数。compression_level 0 表示使用最高质量的编码策略。
    public var ffmpegArguments: [String] {
        ffmpegArguments(forSampleRate: 48_000)
    }

    /// 是否为固定码率档位。
    public var isCBR: Bool { self != .vbrV0 }

    /// 用户选择的固定码率；VBR 档位返回 nil。
    public var requestedCBRBitrate: Int? {
        switch self {
        case .cbr320: return 320
        case .cbr256: return 256
        case .cbr192: return 192
        case .vbrV0:  return nil
        }
    }

    /// MP3 在不同采样率下允许的最大固定码率。
    /// MPEG-1（32/44.1/48 kHz）最高 320 kbps；MPEG-2（16/22.05/24 kHz）最高 160 kbps；
    /// MPEG-2.5（8/11.025/12 kHz）最高 64 kbps。（单位：Hz / kbps）
    public func effectiveCBRBitrate(forSampleRate sampleRate: Int) -> Int? {
        guard let requested = requestedCBRBitrate else { return nil }
        guard sampleRate > 0 else { return requested }

        let maxBitrate: Int
        switch sampleRate {
        case 32_000...:
            maxBitrate = 320
        case 16_000..<32_000:
            maxBitrate = 160
        default:
            maxBitrate = 64
        }
        return min(requested, maxBitrate)
    }

    /// 根据源采样率给出实际可用的 ffmpeg 编码参数。
    /// 低采样率素材不再显示“320k”却输出 160k/64k，而是显式按合法上限编码。
    public func ffmpegArguments(forSampleRate sampleRate: Int) -> [String] {
        guard let bitrate = effectiveCBRBitrate(forSampleRate: sampleRate) else {
            return ["-c:a", "libmp3lame", "-q:a", "0", "-compression_level", "0"]
        }
        return ["-c:a", "libmp3lame", "-b:a", "\(bitrate)k", "-compression_level", "0"]
    }
}

// MARK: - 封面策略

public enum CoverPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 优先内嵌封面，其次第 1 秒、第 2 秒、第 0 秒画面。
    case smart
    /// 忽略内嵌封面，始终截取视频画面。
    case frameOnly
    /// 不写入封面。
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smart:     return "智能封面"
        case .frameOnly: return "截取画面"
        case .none:      return "不添加封面"
        }
    }

    public var detail: String {
        switch self {
        case .smart:
            return "优先使用视频自带封面；没有时截取第 1 秒画面，失败再取第 2 秒。"
        case .frameOnly:
            return "不使用视频自带封面，始终截取视频第 1 秒画面。"
        case .none:
            return "只导出音频，不写入封面图。"
        }
    }
}

// MARK: - 输出行为

public enum ConflictPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case rename
    case overwrite
    case skip

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rename:    return "自动重命名"
        case .overwrite: return "直接覆盖"
        case .skip:      return "跳过已存在"
        }
    }

    public var detail: String {
        switch self {
        case .rename:    return "遇到同名文件时自动加 (1)、(2) 后缀，不丢原文件。"
        case .overwrite: return "同名文件会被新生成的 MP3 替换。"
        case .skip:      return "同名文件已存在时不处理该视频。"
        }
    }
}

// MARK: - 转换设置

public struct ConversionSettings: Sendable, Equatable {
    public var quality: MP3Quality
    public var coverPolicy: CoverPolicy
    public var preserveMetadata: Bool
    public var conflictPolicy: ConflictPolicy
    /// nil 表示输出到视频所在目录。
    public var outputDirectory: URL?
    /// 指定音轨的绝对 stream index；nil 表示使用容器默认音轨。
    public var audioStreamIndex: Int?
    /// 在自定义输出目录下保留的源文件相对子目录；nil 表示直接输出到根目录。
    public var outputSubdirectory: String?

    public init(
        quality: MP3Quality = .cbr320,
        coverPolicy: CoverPolicy = .smart,
        preserveMetadata: Bool = true,
        conflictPolicy: ConflictPolicy = .rename,
        outputDirectory: URL? = nil,
        audioStreamIndex: Int? = nil,
        outputSubdirectory: String? = nil
    ) {
        self.quality = quality
        self.coverPolicy = coverPolicy
        self.preserveMetadata = preserveMetadata
        self.conflictPolicy = conflictPolicy
        self.outputDirectory = outputDirectory
        self.audioStreamIndex = audioStreamIndex
        self.outputSubdirectory = outputSubdirectory
    }
}

// MARK: - 封面来源

public enum CoverOrigin: Equatable, Sendable {
    case embedded
    case frame(seconds: Double)
    case none

    public var displayName: String {
        switch self {
        case .embedded:          return "视频内嵌封面"
        case .frame(let second): return String(format: "视频第 %.0f 秒画面", second)
        case .none:              return "无封面"
        }
    }
}

// MARK: - 进度与结果

public enum ConversionStage: Equatable, Sendable {
    case waiting
    case probing
    case preparingCover
    case encoding

    public var displayName: String {
        switch self {
        case .waiting:        return "等待中"
        case .probing:        return "读取视频信息"
        case .preparingCover: return "提取封面"
        case .encoding:       return "转换音频"
        }
    }
}

public struct ConversionProgress: Sendable, Equatable {
    public let stage: ConversionStage
    /// 0...1
    public let fraction: Double

    public init(stage: ConversionStage, fraction: Double) {
        self.stage = stage
        self.fraction = min(max(fraction, 0), 1)
    }
}

public struct ConversionResult: Sendable {
    public let outputURL: URL
    public let sourceDuration: Double
    public let outputFileSize: Int64
    public let coverOrigin: CoverOrigin
    public let warnings: [String]
    /// 实际采用的音频码率（VBR 或无法判断时为 nil）。
    public let effectiveAudioBitrate: Int?
    /// 源音轨采样率，用于解释低采样率下的码率上限。
    public let sourceAudioSampleRate: Int?

    public init(
        outputURL: URL,
        sourceDuration: Double,
        outputFileSize: Int64,
        coverOrigin: CoverOrigin,
        warnings: [String],
        effectiveAudioBitrate: Int? = nil,
        sourceAudioSampleRate: Int? = nil
    ) {
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.outputFileSize = outputFileSize
        self.coverOrigin = coverOrigin
        self.warnings = warnings
        self.effectiveAudioBitrate = effectiveAudioBitrate
        self.sourceAudioSampleRate = sourceAudioSampleRate
    }
}

// MARK: - 错误

public enum SoundDistillError: LocalizedError, Equatable {
    case ffmpegNotFound
    case probeFailed(String)
    case noAudioTrack
    case coverExtractionFailed(String)
    case encodingFailed(String)
    case outputExists(URL)
    case outputInUse(URL)
    case invalidOutput(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "未找到 ffmpeg。请安装 ffmpeg（brew install ffmpeg）后重试。"
        case .probeFailed(let message):
            return "读取视频信息失败：\(message)"
        case .noAudioTrack:
            return "视频中没有可提取的音轨。"
        case .coverExtractionFailed(let message):
            return "提取封面失败：\(message)"
        case .encodingFailed(let message):
            return "转换失败：\(message)"
        case .outputExists(let url):
            return "输出文件已存在：\(url.lastPathComponent)"
        case .outputInUse(let url):
            return "同名输出正在被另一个任务写入：\(url.lastPathComponent)"
        case .invalidOutput(let message):
            return "生成的音频无效：\(message)"
        case .cancelled:
            return "已取消"
        }
    }
}
