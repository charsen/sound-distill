import Foundation
import SoundDistillCore

@main
struct SoundDistillCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try await run(arguments: arguments)
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    // MARK: - 参数

    private struct Options {
        var command = "convert"
        var inputs: [URL] = []
        var outputDirectory: URL?
        var quality: MP3Quality = .cbr320
        var coverPolicy: CoverPolicy = .smart
        var conflictPolicy: ConflictPolicy = .rename
        var preserveMetadata = true
        var audioStreamIndex: Int?
        var jobs = 2
        var json = false
    }

    private static func usageText() -> String {
        """
        音萃 SoundDistill · 视频转高音质 MP3

        用法：
          sounddistill convert <文件或文件夹>... [选项]
          sounddistill probe <文件> [--json]

        选项：
          -o, --output <目录>      输出目录（默认与视频同目录）
          --quality <320|v0|256|192>  音质档位（默认 320）
          --cover <smart|frame|none>  封面策略（默认 smart）
          --conflict <rename|overwrite|skip>  同名文件处理（默认 rename）
          --audio-index <n>        选择音轨（probe --json 可查看 stream index；默认跟随容器）
          --no-metadata            不复制视频元数据
          --jobs <1-8>             并发数（默认 2）
          --json                   以 JSON 输出结果
          -h, --help               显示帮助
        """
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        if let first = arguments.first, !first.hasPrefix("-"), ["convert", "probe"].contains(first) {
            options.command = first
            index = 1
        }
        if options.command == "probe" {
            // probe 只接受一个文件与 --json
            while index < arguments.count {
                let arg = arguments[index]
                if arg == "--json" { options.json = true }
                else if arg == "-h" || arg == "--help" { print(usageText()); exit(0) }
                else if !arg.hasPrefix("-") { options.inputs.append(URL(fileURLWithPath: arg)) }
                index += 1
            }
            guard options.inputs.count == 1 else { throw CLIError.usage("probe 需要一个文件参数") }
            return options
        }

        while index < arguments.count {
            let arg = arguments[index]
            func nextValue(_ name: String) throws -> String {
                index += 1
                guard index < arguments.count else { throw CLIError.usage("\(name) 缺少参数值") }
                return arguments[index]
            }
            switch arg {
            case "-h", "--help":
                print(usageText())
                exit(0)
            case "-o", "--output":
                options.outputDirectory = URL(fileURLWithPath: try nextValue(arg), isDirectory: true)
            case "--quality":
                let value = try nextValue(arg)
                guard let quality = MP3Quality(rawValue: mapQuality(value)) else {
                    throw CLIError.usage("未知音质档位：\(value)")
                }
                options.quality = quality
            case "--cover":
                let value = try nextValue(arg)
                guard let policy = CoverPolicy(rawValue: mapCover(value)) else {
                    throw CLIError.usage("未知封面策略：\(value)")
                }
                options.coverPolicy = policy
            case "--conflict":
                let value = try nextValue(arg)
                guard let policy = ConflictPolicy(rawValue: value) else {
                    throw CLIError.usage("未知同名策略：\(value)")
                }
                options.conflictPolicy = policy
            case "--audio-index", "--audio":
                let value = try nextValue(arg)
                guard let index = Int(value), index >= 0 else {
                    throw CLIError.usage("--audio-index 需要非负整数")
                }
                options.audioStreamIndex = index
            case "--no-metadata":
                options.preserveMetadata = false
            case "--jobs":
                let value = try nextValue(arg)
                guard let count = Int(value), (1...8).contains(count) else {
                    throw CLIError.usage("--jobs 取值 1-8")
                }
                options.jobs = count
            case "--json":
                options.json = true
            default:
                guard !arg.hasPrefix("-") else { throw CLIError.usage("未知参数：\(arg)") }
                options.inputs.append(URL(fileURLWithPath: arg))
            }
            index += 1
        }
        guard !options.inputs.isEmpty else {
            throw CLIError.usage("请提供至少一个视频文件或文件夹")
        }
        return options
    }

    private static func mapQuality(_ value: String) -> String {
        switch value.lowercased() {
        case "320", "320k": return "cbr320"
        case "v0", "vbr": return "vbrV0"
        case "256", "256k": return "cbr256"
        case "192", "192k": return "cbr192"
        default: return value
        }
    }

    private static func mapCover(_ value: String) -> String {
        switch value.lowercased() {
        case "frame", "frameonly": return "frameOnly"
        case "smart": return "smart"
        case "none": return "none"
        default: return value
        }
    }

    private enum CLIError: LocalizedError {
        case usage(String)
        var errorDescription: String? {
            switch self {
            case .usage(let message): return message + "\n\n" + usageText()
            }
        }
    }

    // MARK: - 执行

    private static func run(arguments: [String]) async throws {
        let options = try parse(arguments)
        let tools = try FFmpegTools.locate()
        let service = ConversionService(tools: tools)

        if options.command == "probe" {
            let info = try await service.probeVideo(options.inputs[0])
            printProbe(info, json: options.json)
            return
        }

        let files = MediaTypes.collectMediaFiles(from: options.inputs)
        guard !files.isEmpty else {
            throw CLIError.usage("没有找到支持的视频文件")
        }

        let settings = ConversionSettings(
            quality: options.quality,
            coverPolicy: options.coverPolicy,
            preserveMetadata: options.preserveMetadata,
            conflictPolicy: options.conflictPolicy,
            outputDirectory: options.outputDirectory,
            audioStreamIndex: options.audioStreamIndex
        )

        if !options.json {
            print("音萃 SoundDistill：共 \(files.count) 个视频，并发 \(options.jobs)，音质 \(options.quality.displayName)")
        }
        let startedAt = Date()

        var outcomes: [Outcome] = []
        await withTaskGroup(of: Outcome.self) { group in
            var nextIndex = 0
            let initial = min(options.jobs, files.count)
            for _ in 0..<initial {
                let file = files[nextIndex]; nextIndex += 1
                group.addTask { await convertOne(file, service: service, settings: settings) }
            }
            for await outcome in group {
                outcomes.append(outcome)
                if !options.json {
                    printOutcome(outcome)
                }
                if nextIndex < files.count {
                    let file = files[nextIndex]; nextIndex += 1
                    group.addTask { await convertOne(file, service: service, settings: settings) }
                }
            }
        }

        outcomes.sort { $0.input.path.localizedStandardCompare($1.input.path) == .orderedAscending }
        let succeeded = outcomes.filter { $0.result != nil }.count
        let skipped = outcomes.filter { $0.skipped }.count
        let failed = outcomes.count - succeeded - skipped
        let elapsed = Date().timeIntervalSince(startedAt)
        if !options.json {
            print(String(format: "\n完成：成功 %d，跳过 %d，失败 %d，用时 %.1f 秒", succeeded, skipped, failed, elapsed))
        }

        if options.json {
            printJSON(outcomes: outcomes)
        }
        if failed > 0 { exit(2) }
    }

    private struct Outcome: Sendable {
        let input: URL
        var result: ConversionResult?
        var errorMessage: String?
        var skipped = false
    }

    private static func convertOne(_ input: URL, service: ConversionService, settings: ConversionSettings) async -> Outcome {
        do {
            let result = try await service.convert(input: input, settings: settings) { _ in }
            return Outcome(input: input, result: result)
        } catch SoundDistillError.outputExists {
            return Outcome(input: input, skipped: true)
        } catch {
            return Outcome(input: input, errorMessage: error.localizedDescription)
        }
    }

    private static func printOutcome(_ outcome: Outcome) {
        if let result = outcome.result {
            let megabytes = Double(result.outputFileSize) / 1_048_576
            let bitrate = result.effectiveAudioBitrate.map { " · \($0) kbps" } ?? ""
            print(String(format: "  ✓ %@ → %@  %.1f MB%@ · %@", outcome.input.lastPathComponent, result.outputURL.lastPathComponent, megabytes, bitrate, result.coverOrigin.displayName))
            for warning in result.warnings {
                print("    ⚠︎ \(warning)")
            }
        } else if outcome.skipped {
            print("  ↷ \(outcome.input.lastPathComponent)：已存在，跳过")
        } else {
            print("  ✗ \(outcome.input.lastPathComponent)：\(outcome.errorMessage ?? "未知错误")")
        }
    }

    private static func printProbe(_ info: VideoInfo, json: Bool) {
        if json {
            let object: [String: Any] = [
                "file": info.url.path,
                "duration": info.duration,
                "format": info.formatName,
                "size": info.fileSize,
                "audio": info.audioStreams.map { [
                    "index": $0.index,
                    "codec": $0.codecName,
                    "channels": $0.channels,
                    "sample_rate": $0.sampleRate,
                    "language": $0.language ?? "",
                    "title": $0.title ?? "",
                    "default": $0.isDefault
                ] },
                "covers": info.coverCandidates.map { ["index": $0.streamIndex, "kind": "\($0.kind)", "width": $0.width ?? 0, "height": $0.height ?? 0] }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }
        print("文件：\(info.url.path)")
        print("时长：\(info.displayDuration)  格式：\(info.formatName)  大小：\(info.fileSize / 1_048_576) MB")
        print("音轨：\(info.audioStreams.count) 条" + (info.primaryAudioStream.map { "，默认 \($0.codecName) / \($0.channelDescription) / \($0.sampleRate) Hz" } ?? ""))
        for stream in info.audioStreams {
            print("  #\(stream.index) \(stream.displayLabel)")
        }
        if info.coverCandidates.isEmpty {
            print("内嵌封面：无")
        } else {
            print("内嵌封面：\(info.coverCandidates.map(\.displayDescription).joined(separator: "；"))")
        }
    }

    private static func printJSON(outcomes: [Outcome]) {
        let items: [[String: Any]] = outcomes.map { outcome in
            if let result = outcome.result {
                return [
                    "input": outcome.input.path,
                    "output": result.outputURL.path,
                    "status": "success",
                    "size": result.outputFileSize,
                    "cover": result.coverOrigin.displayName,
                    "effective_bitrate": result.effectiveAudioBitrate ?? 0,
                    "source_sample_rate": result.sourceAudioSampleRate ?? 0,
                    "warnings": result.warnings
                ]
            }
            if outcome.skipped {
                return ["input": outcome.input.path, "status": "skipped"]
            }
            return ["input": outcome.input.path, "status": "failed", "error": outcome.errorMessage ?? "unknown"]
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["items": items], options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}
