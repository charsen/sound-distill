import XCTest
@testable import SoundDistillCore

final class CommandBuilderTests: XCTestCase {
    private func makeInfo(
        duration: Double = 12,
        audioChannels: Int = 2,
        sampleRate: Int = 48000,
        cover: [CoverCandidate] = [],
        metadata: [String: String] = [:]
    ) -> VideoInfo {
        VideoInfo(
            url: URL(fileURLWithPath: "/tmp/示例 视频.mp4"),
            duration: duration,
            formatName: "mov,mp4",
            fileSize: 1024,
            audioStreams: [
                AudioStreamInfo(index: 1, codecName: "aac", channels: audioChannels, sampleRate: sampleRate, bitRate: 192_000, language: "zh", title: nil)
            ],
            coverCandidates: cover,
            metadata: metadata,
            videoWidth: 1920,
            videoHeight: 1080,
            frameRate: 30
        )
    }

    func testCBR320UsesHighestBitrateAndNoUpscale() {
        let info = makeInfo(metadata: ["title": "测试标题", "artist": "歌手"])
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/out.mp3"),
            info: info,
            coverURL: URL(fileURLWithPath: "/tmp/cover.jpg"),
            settings: ConversionSettings(quality: .cbr320)
        )
        XCTAssertTrue(args.containsSequence(["-b:a", "320k"]))
        XCTAssertTrue(args.containsSequence(["-c:a", "libmp3lame"]))
        XCTAssertTrue(args.containsSequence(["-map", "0:1"]))
        XCTAssertTrue(args.containsSequence(["-map", "1:v"]))
        XCTAssertTrue(args.containsSequence(["-metadata", "title=测试标题"]))
        XCTAssertTrue(args.containsSequence(["-metadata", "artist=歌手"]))
        XCTAssertTrue(args.containsSequence(["-id3v2_version", "3"]))
        XCTAssertTrue(args.containsSequence(["-disposition:v:0", "attached_pic"]))
    }

    func testVBRV0Arguments() {
        let info = makeInfo()
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/out.mp3"),
            info: info,
            coverURL: nil,
            settings: ConversionSettings(quality: .vbrV0)
        )
        XCTAssertTrue(args.containsSequence(["-q:a", "0"]))
        XCTAssertFalse(args.contains("-b:a"))
        XCTAssertFalse(args.contains("1:v"))
    }

    func testSurroundAudioDownmixedAndHighSampleRateLimited() {
        let info = makeInfo(audioChannels: 6, sampleRate: 96_000)
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/out.mp3"),
            info: info,
            coverURL: nil,
            settings: ConversionSettings()
        )
        XCTAssertTrue(args.containsSequence(["-ac", "2"]))
        XCTAssertTrue(args.containsSequence(["-ar", "48000"]))
    }

    func testTitleFallsBackToFilename() {
        let info = makeInfo()
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/out.mp3"),
            info: info,
            coverURL: nil,
            settings: ConversionSettings()
        )
        XCTAssertTrue(args.containsSequence(["-metadata", "title=示例 视频"]))
    }
}

final class OutputPathResolverTests: XCTestCase {
    func testRenamesWhenFileExists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("片段.mp3")
        FileManager.default.createFile(atPath: existing.path, contents: Data("x".utf8))

        let input = directory.appendingPathComponent("片段.mkv")
        let resolved = try OutputPathResolver.resolve(
            input: input,
            settings: ConversionSettings(conflictPolicy: .rename, outputDirectory: directory)
        )
        XCTAssertEqual(resolved.lastPathComponent, "片段 (1).mp3")
    }

    func testSkipThrowsWhenFileExists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appendingPathComponent("片段.mp3").path, contents: Data())

        XCTAssertThrowsError(
            try OutputPathResolver.resolve(
                input: directory.appendingPathComponent("片段.mp4"),
                settings: ConversionSettings(conflictPolicy: .skip, outputDirectory: directory)
            )
        ) { error in
            guard case SoundDistillError.outputExists = error else {
                return XCTFail("expected outputExists, got \(error)")
            }
        }
    }

    func testCustomOutputSubdirectoryIsApplied() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try OutputPathResolver.resolve(
            input: directory.appendingPathComponent("片段.mp4"),
            settings: ConversionSettings(
                conflictPolicy: .rename,
                outputDirectory: directory,
                outputSubdirectory: "子目录/第二层"
            )
        )
        XCTAssertEqual(resolved.deletingLastPathComponent().path, directory.appendingPathComponent("子目录/第二层").path)
        XCTAssertEqual(resolved.lastPathComponent, "片段.mp3")
    }

    func testOverwriteKeepsDirectPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appendingPathComponent("片段.mp3").path, contents: Data())

        let resolved = try OutputPathResolver.resolve(
            input: directory.appendingPathComponent("片段.mp4"),
            settings: ConversionSettings(conflictPolicy: .overwrite, outputDirectory: directory)
        )
        XCTAssertEqual(resolved.lastPathComponent, "片段.mp3")
    }
}

final class ProbeParserTests: XCTestCase {
    private func parse(_ json: String) throws -> VideoInfo {
        let data = Data(json.utf8)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try MediaProbe.parse(root: root, url: URL(fileURLWithPath: "/tmp/input.mp4"))
    }

    func testParsesEmbeddedCoverAndMetadata() throws {
        let info = try parse("""
        {
          "format": {"duration": "65.5", "size": "10485760", "format_name": "mov,mp4", "tags": {"title": "测试影片", "artist": "张三"}},
          "streams": [
            {"index": 0, "codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080, "avg_frame_rate": "30000/1001"},
            {"index": 1, "codec_type": "audio", "codec_name": "aac", "channels": 2, "sample_rate": "48000", "bit_rate": "192000", "tags": {"language": "zh"}},
            {"index": 2, "codec_type": "video", "codec_name": "mjpeg", "width": 600, "height": 600, "disposition": {"attached_pic": 1}}
          ]
        }
        """)
        XCTAssertEqual(info.duration, 65.5)
        XCTAssertEqual(info.audioStreams.count, 1)
        XCTAssertEqual(info.audioStreams[0].channels, 2)
        XCTAssertEqual(info.coverCandidates.count, 1)
        XCTAssertEqual(info.coverCandidates[0].kind, .attachedPicture)
        XCTAssertEqual(info.coverCandidates[0].width, 600)
        XCTAssertEqual(info.metadata["title"], "测试影片")
        XCTAssertEqual(info.videoWidth, 1920)
        XCTAssertEqual(info.frameRate ?? 0, 29.97, accuracy: 0.01)
    }

    func testParsesMKVAttachmentAndTimecodeDuration() throws {
        let info = try parse("""
        {
          "format": {"format_name": "matroska,webm", "tags": {}},
          "streams": [
            {"index": 0, "codec_type": "video", "codec_name": "h264", "width": 1280, "height": 720, "tags": {"DURATION": "00:01:05.500000000"}},
            {"index": 1, "codec_type": "audio", "codec_name": "ac3", "channels": 6, "sample_rate": "48000"},
            {"index": 2, "codec_type": "attachment", "codec_name": "mjpeg", "tags": {"mimetype": "image/jpeg", "filename": "cover.jpg"}}
          ]
        }
        """)
        XCTAssertEqual(info.duration, 65.5, accuracy: 0.001)
        XCTAssertEqual(info.coverCandidates.count, 1)
        XCTAssertEqual(info.coverCandidates[0].kind, .attachment)
        XCTAssertEqual(info.coverCandidates[0].filename, "cover.jpg")
    }

    func testFormatDurationZeroFallsBackToStreamDuration() throws {
        let info = try parse("""
        {
          "format": {"duration": "0.000000", "format_name": "matroska,webm"},
          "streams": [
            {"index": 0, "codec_type": "audio", "codec_name": "aac", "channels": 2, "sample_rate": "48000", "tags": {"DURATION": "00:00:30.500000000"}}
          ]
        }
        """)
        XCTAssertEqual(info.duration, 30.5, accuracy: 0.001)
    }

    func testPrimaryAudioPrefersDefaultStream() throws {
        let info = try parse("""
        {
          "format": {"duration": "10", "format_name": "matroska,webm"},
          "streams": [
            {"index": 0, "codec_type": "audio", "codec_name": "aac", "channels": 2, "sample_rate": "48000", "disposition": {"default": 0}},
            {"index": 1, "codec_type": "audio", "codec_name": "ac3", "channels": 2, "sample_rate": "48000", "disposition": {"default": 1}}
          ]
        }
        """)
        XCTAssertEqual(info.primaryAudioStream?.index, 1)
    }

    func testNoAudioTrackThrows() {
        let json = """
        {"format": {"duration": "10"}, "streams": [{"index": 0, "codec_type": "video", "codec_name": "h264"}]}
        """
        XCTAssertThrowsError(try parse(json)) { error in
            guard case SoundDistillError.noAudioTrack = error else {
                return XCTFail("expected noAudioTrack, got \(error)")
            }
        }
    }
}

final class QualityTests: XCTestCase {
    func testEffectiveBitrateRespectsMPEGSampleRateLimits() {
        XCTAssertEqual(MP3Quality.cbr320.effectiveCBRBitrate(forSampleRate: 48_000), 320)
        XCTAssertEqual(MP3Quality.cbr320.effectiveCBRBitrate(forSampleRate: 22_050), 160)
        XCTAssertEqual(MP3Quality.cbr320.effectiveCBRBitrate(forSampleRate: 8_000), 64)
        XCTAssertEqual(MP3Quality.cbr192.effectiveCBRBitrate(forSampleRate: 16_000), 160)
        XCTAssertNil(MP3Quality.vbrV0.effectiveCBRBitrate(forSampleRate: 48_000))
    }

    func testCommandUsesEffectiveBitrateForLowSampleSource() {
        let info = VideoInfo(
            url: URL(fileURLWithPath: "/tmp/low.mp4"),
            duration: 5,
            formatName: "mp4",
            fileSize: 100,
            audioStreams: [
                AudioStreamInfo(index: 1, codecName: "aac", channels: 2, sampleRate: 22_050, bitRate: 128_000, language: nil, title: nil)
            ],
            coverCandidates: [],
            metadata: [:],
            videoWidth: 320,
            videoHeight: 240,
            frameRate: 25
        )
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/low.mp3"),
            info: info,
            coverURL: nil,
            settings: ConversionSettings(quality: .cbr320)
        )
        XCTAssertTrue(args.containsSequence(["-b:a", "160k"]))
    }

    func testSelectedAudioStreamIndexOverridesDefault() {
        let info = VideoInfo(
            url: URL(fileURLWithPath: "/tmp/multi.mkv"),
            duration: 5,
            formatName: "matroska",
            fileSize: 100,
            audioStreams: [
                AudioStreamInfo(index: 1, codecName: "aac", channels: 2, sampleRate: 48_000, bitRate: nil, language: "jpn", title: "日语", isDefault: true),
                AudioStreamInfo(index: 3, codecName: "ac3", channels: 6, sampleRate: 48_000, bitRate: nil, language: "zho", title: "国语", isDefault: false)
            ],
            coverCandidates: [],
            metadata: [:],
            videoWidth: 320,
            videoHeight: 240,
            frameRate: 25
        )
        let args = FFmpegCommandBuilder.encodingArguments(
            input: info.url,
            output: URL(fileURLWithPath: "/tmp/multi.mp3"),
            info: info,
            coverURL: nil,
            settings: ConversionSettings(quality: .cbr320, audioStreamIndex: 3)
        )
        XCTAssertTrue(args.containsSequence(["-map", "0:3"]))
        XCTAssertTrue(args.containsSequence(["-ac", "2"]))
    }
}

final class ProgressParserTests: XCTestCase {
    func testParsesOutTimeMicroseconds() {
        XCTAssertEqual(ConversionService.progressFraction(from: "out_time_us=2500000", duration: 10) ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(ConversionService.progressFraction(from: "out_time_ms=1000000", duration: 10) ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertNil(ConversionService.progressFraction(from: "progress=continue", duration: 10))
    }
}

private extension Array where Element == String {
    func containsSequence(_ sequence: [String]) -> Bool {
        guard !sequence.isEmpty, count >= sequence.count else { return false }
        for start in 0...(count - sequence.count) {
            if Array(self[start..<(start + sequence.count)]) == sequence { return true }
        }
        return false
    }
}
