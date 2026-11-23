import Foundation

/// 集中构造 ffmpeg 参数，便于单元测试覆盖。
public enum FFmpegCommandBuilder {
    /// 封面最长边限制，避免把超大海报原样塞进 MP3 导致文件膨胀。
    public static let maxCoverDimension = 1400

    private static var coverScaleFilter: String {
        "scale='min(\(maxCoverDimension),iw)':'min(\(maxCoverDimension),ih)':force_original_aspect_ratio=decrease"
    }

    /// 从内嵌封面流提取一张 JPEG。
    public static func coverExtractionArguments(input: URL, candidate: CoverCandidate, destination: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-v", "error", "-y",
            "-i", input.path,
            "-map", "0:\(candidate.streamIndex)",
            "-frames:v", "1",
            "-vf", coverScaleFilter,
            "-c:v", "mjpeg",
            "-q:v", "2",
            "-f", "image2",
            destination.path
        ]
    }

    /// 从指定时间点截取一帧 JPEG。
    public static func frameExtractionArguments(input: URL, at seconds: Double, destination: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-v", "error", "-y",
            "-ss", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds)),
            "-i", input.path,
            "-frames:v", "1",
            "-vf", coverScaleFilter,
            "-c:v", "mjpeg",
            "-q:v", "2",
            "-f", "image2",
            destination.path
        ]
    }

    /// 主转码命令：视频音轨 -> MP3，并可选写入封面与 ID3 标签。
    public static func encodingArguments(
        input: URL,
        output: URL,
        info: VideoInfo,
        coverURL: URL?,
        settings: ConversionSettings
    ) -> [String] {
        var arguments: [String] = [
            "-hide_banner", "-nostdin", "-v", "error", "-y",
            "-i", input.path
        ]

        if let coverURL {
            arguments += ["-i", coverURL.path]
        }

        // 优先使用用户选择的音轨；未选择时取容器标记为 default 的主音轨。
        let primaryAudio = settings.audioStreamIndex.flatMap { index in
            info.audioStreams.first(where: { $0.index == index })
        } ?? info.primaryAudioStream
        arguments += ["-map", primaryAudio.map { "0:\($0.index)" } ?? "0:a:0"]

        if coverURL != nil {
            arguments += ["-map", "1:v"]
        }

        arguments += settings.quality.ffmpegArguments(forSampleRate: primaryAudio?.sampleRate ?? 0)

        if let audio = primaryAudio {
            // MP3 最多两声道；5.1 等环绕声先下混，保证兼容性。
            if audio.channels > 2 {
                arguments += ["-ac", "2"]
            }
            // MP3 采样率上限为 48 kHz，96 kHz 以上素材降采样到 48 kHz。
            if audio.sampleRate > 48_000 {
                arguments += ["-ar", "48000"]
            }
        }

        // 先清空容器元数据，再写入受控的 ID3 字段，避免带出 major_brand 等无关标签。
        arguments += ["-map_metadata", "-1", "-map_chapters", "-1"]
        arguments += metadataArguments(info: info, preserveMetadata: settings.preserveMetadata)

        if coverURL != nil {
            arguments += [
                "-c:v", "mjpeg",
                "-q:v", "2",
                "-disposition:v:0", "attached_pic",
                "-metadata:s:v:0", "title=Album cover",
                "-metadata:s:v:0", "comment=Cover (front)"
            ]
        }

        arguments += [
            "-id3v2_version", "3",
            "-write_id3v1", "0",
            "-write_xing", "1",
            "-progress", "pipe:1",
            "-nostats",
            output.path
        ]

        return arguments
    }

    /// 复制常见元数据；标题缺失时回退到文件名。
    public static func metadataArguments(info: VideoInfo, preserveMetadata: Bool) -> [String] {
        var values: [String: String] = [:]
        let copyableKeys = [
            "title", "artist", "album", "album_artist", "date", "genre",
            "comment", "composer", "track", "disc", "copyright"
        ]
        if preserveMetadata {
            for key in copyableKeys {
                if let value = info.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    values[key] = value
                }
            }
        }
        if values["title"] == nil {
            let fallback = info.url.deletingPathExtension().lastPathComponent
            if !fallback.isEmpty {
                values["title"] = fallback
            }
        }

        var arguments: [String] = []
        for key in copyableKeys {
            if let value = values[key] {
                arguments += ["-metadata", "\(key)=\(value)"]
            }
        }
        return arguments
    }
}
