import Foundation

/// 定位 ffmpeg / ffprobe。应用包优先使用内置版本，其次回退到本机 Homebrew 安装。
public struct FFmpegTools: Sendable, Equatable {
    public let ffmpegURL: URL
    public let ffprobeURL: URL

    public init(ffmpegURL: URL, ffprobeURL: URL) {
        self.ffmpegURL = ffmpegURL
        self.ffprobeURL = ffprobeURL
    }

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> FFmpegTools {
        let fm = FileManager.default

        var candidateDirectories: [URL] = []

        // 1. 显式环境变量（开发调试 / 自动化测试）
        if let custom = environment["AUDIOEXTRACT_FFMPEG_DIR"], !custom.isEmpty {
            candidateDirectories.append(URL(fileURLWithPath: custom, isDirectory: true))
        }

        // 2. App 包内置：Contents/Resources/ffmpeg/bin
        if let resourceURL = Bundle.main.resourceURL {
            candidateDirectories.append(resourceURL.appendingPathComponent("ffmpeg/bin", isDirectory: true))
        }
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/ffmpeg/bin", isDirectory: true)
        candidateDirectories.append(bundleCandidate)

        // 3. 可执行文件旁边的 Resources（swift run 场景）
        if let executableURL = Bundle.main.executableURL {
            let macOSDir = executableURL.deletingLastPathComponent()
            candidateDirectories.append(macOSDir.deletingLastPathComponent().appendingPathComponent("Resources/ffmpeg/bin", isDirectory: true))
        }

        // 4. Homebrew 常见路径
        candidateDirectories.append(URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true))
        candidateDirectories.append(URL(fileURLWithPath: "/usr/local/bin", isDirectory: true))

        // 5. 当前 PATH
        if let pathValue = environment["PATH"] {
            for component in pathValue.split(separator: ":") where !component.isEmpty {
                candidateDirectories.append(URL(fileURLWithPath: String(component), isDirectory: true))
            }
        }

        var seen = Set<String>()
        for directory in candidateDirectories {
            let key = directory.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            let ffmpeg = directory.appendingPathComponent("ffmpeg")
            let ffprobe = directory.appendingPathComponent("ffprobe")
            if fm.isExecutableFile(atPath: ffmpeg.path) && fm.isExecutableFile(atPath: ffprobe.path) {
                return FFmpegTools(ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
            }
        }

        throw SoundDistillError.ffmpegNotFound
    }

    /// 检查工具链是否可用，用于界面启动提示。
    public static func isAvailable() -> Bool {
        (try? locate()) != nil
    }
}
