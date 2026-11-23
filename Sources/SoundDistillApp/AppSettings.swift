import Foundation
import SoundDistillCore

/// 应用设置。持久化到 UserDefaults，转换时映射为核心层的 ConversionSettings。
struct AppSettings: Codable, Equatable {
    var quality: MP3Quality = .cbr320
    var coverPolicy: CoverPolicy = .smart
    var conflictPolicy: ConflictPolicy = .rename
    var preserveMetadata = true
    var useCustomOutput = false
    var customOutputPath = ""
    /// 自定义输出目录时，保留导入文件夹内的相对目录结构。
    var preserveFolderStructure = false
    var concurrency = 2
    var playSoundOnFinish = true

    private enum CodingKeys: String, CodingKey {
        case quality, coverPolicy, conflictPolicy, preserveMetadata
        case useCustomOutput, customOutputPath, preserveFolderStructure
        case concurrency, playSoundOnFinish
    }

    init(
        quality: MP3Quality = .cbr320,
        coverPolicy: CoverPolicy = .smart,
        conflictPolicy: ConflictPolicy = .rename,
        preserveMetadata: Bool = true,
        useCustomOutput: Bool = false,
        customOutputPath: String = "",
        preserveFolderStructure: Bool = false,
        concurrency: Int = 2,
        playSoundOnFinish: Bool = true
    ) {
        self.quality = quality
        self.coverPolicy = coverPolicy
        self.conflictPolicy = conflictPolicy
        self.preserveMetadata = preserveMetadata
        self.useCustomOutput = useCustomOutput
        self.customOutputPath = customOutputPath
        self.preserveFolderStructure = preserveFolderStructure
        self.concurrency = concurrency
        self.playSoundOnFinish = playSoundOnFinish
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decodeIfPresent(MP3Quality.self, forKey: .quality) ?? .cbr320
        coverPolicy = try container.decodeIfPresent(CoverPolicy.self, forKey: .coverPolicy) ?? .smart
        conflictPolicy = try container.decodeIfPresent(ConflictPolicy.self, forKey: .conflictPolicy) ?? .rename
        preserveMetadata = try container.decodeIfPresent(Bool.self, forKey: .preserveMetadata) ?? true
        useCustomOutput = try container.decodeIfPresent(Bool.self, forKey: .useCustomOutput) ?? false
        customOutputPath = try container.decodeIfPresent(String.self, forKey: .customOutputPath) ?? ""
        preserveFolderStructure = try container.decodeIfPresent(Bool.self, forKey: .preserveFolderStructure) ?? false
        concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 2
        playSoundOnFinish = try container.decodeIfPresent(Bool.self, forKey: .playSoundOnFinish) ?? true
    }

    var conversionSettings: ConversionSettings {
        var output: URL?
        if useCustomOutput, !customOutputPath.isEmpty {
            output = URL(fileURLWithPath: customOutputPath, isDirectory: true)
        }
        return ConversionSettings(
            quality: quality,
            coverPolicy: coverPolicy,
            preserveMetadata: preserveMetadata,
            conflictPolicy: conflictPolicy,
            outputDirectory: output
        )
    }

    var outputDescription: String {
        if useCustomOutput, !customOutputPath.isEmpty {
            return (customOutputPath as NSString).abbreviatingWithTildeInPath
        }
        return "与视频相同"
    }
}

enum SettingsStore {
    private static let key = "SoundDistill.Settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
