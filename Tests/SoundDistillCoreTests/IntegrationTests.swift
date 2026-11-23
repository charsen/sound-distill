import XCTest
@testable import SoundDistillCore

/// 真实调用 ffmpeg 的端到端测试：构造小视频，验证音轨、封面与命名规则。
/// 在没有 ffmpeg 的开发机上自动跳过。
final class IntegrationTests: XCTestCase {
    private var workDir: URL!
    private var outputDir: URL!
    private var service: ConversionService!

    override func setUpWithError() throws {
        let tools: FFmpegTools
        do {
            tools = try FFmpegTools.locate()
        } catch {
            throw XCTSkip("本机未安装 ffmpeg，跳过集成测试")
        }
        service = ConversionService(tools: tools)
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("SoundDistillTests-\(UUID().uuidString)", isDirectory: true)
        outputDir = workDir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir {
            try? FileManager.default.removeItem(at: workDir)
        }
    }

    func testFullPipeline() async throws {
        let tools = try FFmpegTools.locate()
        let fixtures = try await makeFixtures(tools: tools)

        // 1. MP4 内嵌封面：应优先使用内嵌封面，并输出 320k MP3。
        let covered = try await service.convert(
            input: fixtures.coveredMP4,
            settings: ConversionSettings(quality: .cbr320, coverPolicy: .smart, outputDirectory: outputDir),
            onProgress: { _ in }
        )
        XCTAssertEqual(covered.coverOrigin, .embedded)
        let coveredProbe = try await service.probeVideo(covered.outputURL)
        XCTAssertEqual(coveredProbe.primaryAudioStream?.codecName, "mp3")
        XCTAssertEqual(coveredProbe.primaryAudioStream?.bitRate ?? 0, 320_000)
        XCTAssertEqual(coveredProbe.coverCandidates.count, 1)
        XCTAssertEqual(coveredProbe.coverCandidates[0].codecName, "mjpeg")

        // 2. 无内嵌封面的 MOV：应截取第 1 秒画面。
        let plain = try await service.convert(
            input: fixtures.plainMOV,
            settings: ConversionSettings(quality: .cbr320, coverPolicy: .smart, outputDirectory: outputDir),
            onProgress: { _ in }
        )
        XCTAssertEqual(plain.coverOrigin, .frame(seconds: 1))
        let plainProbe = try await service.probeVideo(plain.outputURL)
        XCTAssertEqual(plainProbe.coverCandidates.count, 1)

        // 3. MKV 封面（attached picture）：应识别为内嵌封面。
        let mkv = try await service.convert(
            input: fixtures.coveredMKV,
            settings: ConversionSettings(quality: .cbr320, coverPolicy: .smart, outputDirectory: outputDir),
            onProgress: { _ in }
        )
        XCTAssertEqual(mkv.coverOrigin, .embedded)

        // 4. 只有 0.6 秒的短视频：1 秒/2 秒都取不到，应退回第 0 秒。
        let short = try await service.convert(
            input: fixtures.shortMOV,
            settings: ConversionSettings(quality: .cbr320, coverPolicy: .smart, outputDirectory: outputDir),
            onProgress: { _ in }
        )
        XCTAssertEqual(short.coverOrigin, .frame(seconds: 0))

        // 5. 同名冲突：第二次转换自动重命名，不覆盖。
        let secondPlain = try await service.convert(
            input: fixtures.plainMOV,
            settings: ConversionSettings(quality: .cbr320, coverPolicy: .smart, outputDirectory: outputDir),
            onProgress: { _ in }
        )
        XCTAssertNotEqual(secondPlain.outputURL, plain.outputURL)
        XCTAssertTrue(secondPlain.outputURL.lastPathComponent.contains("(1)"))

        // 6. 关闭封面：输出不应带视频流。
        let noCover = try await service.convert(
            input: fixtures.plainMOV,
            settings: ConversionSettings(quality: .vbrV0, coverPolicy: .none, outputDirectory: workDir.appendingPathComponent("nocover")),
            onProgress: { _ in }
        )
        XCTAssertEqual(noCover.coverOrigin, .none)
        let noCoverProbe = try await service.probeVideo(noCover.outputURL)
        XCTAssertTrue(noCoverProbe.coverCandidates.isEmpty)
    }

    // MARK: - 夹具

    private struct Fixtures {
        let base: URL
        let coveredMP4: URL
        let coveredMKV: URL
        let plainMOV: URL
        let shortMOV: URL
    }

    private func makeFixtures(tools: FFmpegTools) async throws -> Fixtures {
        let cover = workDir.appendingPathComponent("cover.jpg")
        let base = workDir.appendingPathComponent("base.mp4")
        let coveredMP4 = workDir.appendingPathComponent("covered.mp4")
        let coveredMKV = workDir.appendingPathComponent("covered.mkv")
        let plainMOV = workDir.appendingPathComponent("plain.mov")
        let shortMOV = workDir.appendingPathComponent("short.mov")

        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "color=c=0x1E90FF:s=600x600:d=1",
            "-frames:v", "1", cover.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25:duration=4",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=4",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", base.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y", "-i", base.path, "-i", cover.path,
            "-map", "0", "-map", "1", "-c", "copy", "-disposition:v:1", "attached_pic", coveredMP4.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y", "-i", base.path,
            "-attach", cover.path,
            "-metadata:s:t", "mimetype=image/jpeg",
            "-metadata:s:t", "filename=cover.jpg",
            coveredMKV.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=44100:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", plainMOV.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25:duration=0.6",
            "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=44100:duration=0.6",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", shortMOV.path
        ])

        return Fixtures(base: base, coveredMP4: coveredMP4, coveredMKV: coveredMKV, plainMOV: plainMOV, shortMOV: shortMOV)
    }

    func testLowSampleRatesUseLegalMP3Bitrates() async throws {
        let tools = try FFmpegTools.locate()
        let low22 = workDir.appendingPathComponent("low22.mp4")
        let low8 = workDir.appendingPathComponent("low8.mp4")
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=22050:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", low22.path
        ])
        try await run(tools.ffmpegURL, [
            "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=8000:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", low8.path
        ])

        let settings = ConversionSettings(quality: .cbr320, coverPolicy: .none, outputDirectory: workDir.appendingPathComponent("low-out"))
        let result22 = try await service.convert(input: low22, settings: settings, onProgress: { _ in })
        let result8 = try await service.convert(input: low8, settings: settings, onProgress: { _ in })
        XCTAssertEqual(result22.effectiveAudioBitrate, 160)
        XCTAssertEqual(result8.effectiveAudioBitrate, 64)
        XCTAssertTrue(result22.warnings.contains(where: { $0.contains("22050") && $0.contains("160") }))
        let probe22 = try await service.probeVideo(result22.outputURL)
        let probe8 = try await service.probeVideo(result8.outputURL)
        XCTAssertEqual(probe22.primaryAudioStream?.bitRate, 160_000)
        XCTAssertEqual(probe8.primaryAudioStream?.bitRate, 64_000)
    }

    func testOverwriteDoesNotDeletePreexistingDirectory() async throws {
        let tools = try FFmpegTools.locate()
        let fixtures = try await makeFixtures(tools: tools)
        let sourceDir = workDir.appendingPathComponent("overwriteSource", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let input = sourceDir.appendingPathComponent("clip.mp4")
        try FileManager.default.copyItem(at: fixtures.base, to: input)

        let outputDirectory = workDir.appendingPathComponent("overwriteOut", isDirectory: true)
        let occupied = outputDirectory.appendingPathComponent("clip.mp3", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        let marker = occupied.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)

        let settings = ConversionSettings(quality: .cbr320, coverPolicy: .none, conflictPolicy: .overwrite, outputDirectory: outputDirectory)
        do {
            _ = try await service.convert(input: input, settings: settings, onProgress: { _ in })
            XCTFail("输出路径为文件夹时应失败")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "失败时不得删除既有目录内容")
        }
    }

    func testSkipExistingOutputDoesNotProbeCorruptInput() async throws {
        let outputDirectory = workDir.appendingPathComponent("skipOut", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let existing = outputDirectory.appendingPathComponent("bad.mp3")
        try Data("sentinel".utf8).write(to: existing)
        let badInput = workDir.appendingPathComponent("bad.mp4")
        try Data("not a video".utf8).write(to: badInput)

        let settings = ConversionSettings(conflictPolicy: .skip, outputDirectory: outputDirectory)
        do {
            _ = try await service.convert(input: badInput, settings: settings, onProgress: { _ in })
            XCTFail("已有输出时应直接跳过")
        } catch SoundDistillError.outputExists {
            // 期望路径：在 probe 前识别 skip。
        } catch {
            XCTFail("应返回 outputExists，实际：\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("sentinel".utf8))
    }

    func testOverwriteReplacesExistingFileOnlyAfterSuccess() async throws {
        let tools = try FFmpegTools.locate()
        let fixtures = try await makeFixtures(tools: tools)
        let sourceDir = workDir.appendingPathComponent("overwriteSource2", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let input = sourceDir.appendingPathComponent("clip.mp4")
        try FileManager.default.copyItem(at: fixtures.base, to: input)

        let outputDirectory = workDir.appendingPathComponent("overwriteOut2", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let existing = outputDirectory.appendingPathComponent("clip.mp3")
        try Data("SENTINEL-ORIGINAL".utf8).write(to: existing)

        let settings = ConversionSettings(quality: .cbr320, coverPolicy: .none, conflictPolicy: .overwrite, outputDirectory: outputDirectory)
        let result = try await service.convert(input: input, settings: settings, onProgress: { _ in })
        XCTAssertEqual(result.outputURL, existing)
        let data = try Data(contentsOf: existing)
        XCTAssertGreaterThan(data.count, 1024)
        XCTAssertNotEqual(data, Data("SENTINEL-ORIGINAL".utf8))
    }

    func testConcurrentSameBasenameGetsUniqueOutputs() async throws {
        let tools = try FFmpegTools.locate()
        let fixtures = try await makeFixtures(tools: tools)
        let dirA = workDir.appendingPathComponent("sourceA", isDirectory: true)
        let dirB = workDir.appendingPathComponent("sourceB", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let a = dirA.appendingPathComponent("clip.mp4")
        let b = dirB.appendingPathComponent("clip.mp4")
        try FileManager.default.copyItem(at: fixtures.base, to: a)
        try FileManager.default.copyItem(at: fixtures.base, to: b)

        let settings = ConversionSettings(quality: .cbr320, coverPolicy: .none, outputDirectory: outputDir)
        async let first = service.convert(input: a, settings: settings, onProgress: { _ in })
        async let second = service.convert(input: b, settings: settings, onProgress: { _ in })
        let results = try await [first, second]

        XCTAssertNotEqual(results[0].outputURL, results[1].outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[1].outputURL.path))
        let names = Set(results.map { $0.outputURL.lastPathComponent })
        XCTAssertEqual(names, ["clip.mp3", "clip (1).mp3"])
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws {
        let result = try await ProcessRunner.run(executable: executable, arguments: arguments)
        if !result.succeeded {
            throw XCTSkip("生成测试素材失败：\(result.stderr)")
        }
    }
}
