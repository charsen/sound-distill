import AppKit
import SwiftUI

struct FFmpegMissingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.11))
                        .frame(width: 78, height: 78)
                    Image(systemName: "terminal")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.orange)
                }

                VStack(spacing: 7) {
                    Text("需要安装 ffmpeg")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("音萃使用 ffmpeg 解码视频并编码 MP3。安装后点击重新检测即可，无需重启。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                }

                HStack(spacing: 10) {
                    Text("brew install ffmpeg")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardBackground))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator.opacity(0.5), lineWidth: 0.8))
                    Button {
                        model.copyFFmpegInstallCommand()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .help("复制安装命令")
                }

                HStack(spacing: 10) {
                    Button("重新检测") { model.refreshFFmpeg() }
                        .buttonStyle(PrimaryActionButtonStyle())
                    Button("打开终端") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                Text("已安装但检测不到？请确认 ffmpeg 位于 /opt/homebrew/bin 或 /usr/local/bin。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.separator.opacity(0.5), lineWidth: 0.8)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct HelpView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("音萃 SoundDistill 使用说明")
                        .font(.system(size: 16, weight: .bold))
                    Text("SoundDistill · 从视频提取高音质 MP3")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(SecondaryActionButtonStyle())
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helpSection(
                        icon: "film",
                        title: "支持格式",
                        lines: [
                            "MP4、MKV、MOV、M4V、AVI、WMV、FLV、WebM、TS 等常见视频容器。",
                            "拖入文件或整个文件夹即可批量加入，文件夹会递归扫描。"
                        ]
                    )
                    helpSection(
                        icon: "waveform",
                        title: "音质",
                        lines: [
                            "默认 320 kbps CBR，是 MP3 格式的最高规格；也可选 VBR V0、256、192 kbps。",
                            "使用 LAME 最高质量编码策略（compression_level 0），保留原始采样率（最高 48 kHz）。",
                            "低采样率素材会自动按 MP3 合法上限编码并显示提示，例如 22.05 kHz 最高 160 kbps。",
                            "多音轨视频可在任务行选择音轨，默认跟随容器的默认音轨。",
                            "5.1 等环绕声音轨会自动下混为立体声，保证 MP3 兼容性。"
                        ]
                    )
                    helpSection(
                        icon: "photo.on.rectangle",
                        title: "封面规则",
                        lines: [
                            "智能模式：优先使用视频内嵌封面（MP4 的 covr、MKV 的附件封面）。",
                            "没有内嵌封面时，截取第 1 秒画面；失败再取第 2 秒，极短视频退回第 0 秒。",
                            "封面会以 ID3v2.3 APIC 写入 MP3，macOS 音乐、Finder、第三方播放器均可读取。"
                        ]
                    )
                    helpSection(
                        icon: "square.stack.3d.up",
                        title: "批量与输出",
                        lines: [
                            "默认同时转换 2 个视频，可在右侧设置中调整到 1–8 个。",
                            "输出默认放在视频同目录，文件名与原视频一致；同名文件自动加 (1)、(2) 后缀，不覆盖原文件。",
                            "可选保持原目录结构；未完成任务会自动保存，下次启动恢复队列。",
                            "每批结束会显示成功、失败、跳过和取消数量，并可直接打开输出目录。"
                        ]
                    )
                    helpSection(
                        icon: "keyboard",
                        title: "快捷键",
                        lines: [
                            "⌘O 添加视频；⇧⌘O 添加文件夹。",
                            "⌘↩ 开始转换；⌘. 取消全部。"
                        ]
                    )
                }
                .padding(22)
            }
            .frame(maxHeight: 470)

            Divider()

            HStack {
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                if case .available(let version) = model.ffmpegStatus {
                    Text("ffmpeg \(version)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 580, height: 610)
        .background(Theme.background)
        .focusEffectDisabled()
    }

    private func helpSection(icon: String, title: String, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accentGradient)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
