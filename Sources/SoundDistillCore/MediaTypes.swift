import Foundation

public enum MediaTypes {
    /// ffmpeg 能读取的常见视频/容器扩展名。
    public static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "mov", "avi", "wmv", "flv", "webm",
        "ts", "mts", "m2ts", "3gp", "3g2", "ogv", "mpg", "mpeg",
        "vob", "rm", "rmvb", "asf", "f4v", "mxf", "divx"
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func displayListDescription() -> String {
        ["MP4", "MKV", "MOV", "M4V", "AVI", "WMV", "FLV", "WebM", "TS"].joined(separator: " · ")
    }

    /// 展开拖入的文件/文件夹，去重并保持稳定顺序。
    public static func collectMediaFiles(from urls: [URL], recursive: Bool = true) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        let fileManager = FileManager.default

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard isSupported(standardized) else { return }
            // 符号链接指向同一文件时不应重复入队。
            let canonical = standardized.resolvingSymlinksInPath()
            guard seen.insert(canonical.path).inserted else { return }
            results.append(standardized)
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if recursive {
                    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
                        var found: [URL] = []
                        for case let fileURL as URL in enumerator {
                            let values = try? fileURL.resourceValues(forKeys: Set(keys))
                            if values?.isRegularFile == true {
                                found.append(fileURL)
                            }
                        }
                        for file in found.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
                            append(file)
                        }
                    }
                }
            } else {
                append(url)
            }
        }
        return results
    }
}
