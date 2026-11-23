import Foundation

public enum OutputPathResolver {
    /// 根据设置计算输出路径。
    /// - rename: 同名文件存在时自动加 (1)、(2) 后缀。
    /// - overwrite: 直接使用同名路径。
    /// - skip: 抛 outputExists，由上层标记为跳过。
    public static func resolve(
        input: URL,
        settings: ConversionSettings,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> URL {
        let baseDirectory = settings.outputDirectory ?? input.deletingLastPathComponent()
        let directory: URL
        if let subdirectory = settings.outputSubdirectory, !subdirectory.isEmpty {
            directory = baseDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        } else {
            directory = baseDirectory
        }
        let basename = input.deletingPathExtension().lastPathComponent
        let safeBasename = basename.isEmpty ? "audio" : basename
        let direct = directory.appendingPathComponent(safeBasename).appendingPathExtension("mp3")

        switch settings.conflictPolicy {
        case .overwrite:
            return direct
        case .skip:
            if fileExists(direct.path) {
                throw SoundDistillError.outputExists(direct)
            }
            return direct
        case .rename:
            if !fileExists(direct.path) {
                return direct
            }
            var counter = 1
            while true {
                let candidate = directory
                    .appendingPathComponent("\(safeBasename) (\(counter))")
                    .appendingPathExtension("mp3")
                if !fileExists(candidate.path) {
                    return candidate
                }
                counter += 1
            }
        }
    }
}
