import SwiftUI

struct DropZoneView: View {
    @EnvironmentObject private var model: AppModel
    let isHighlighted: Bool

    private let formats = ["MP4", "MKV", "MOV", "M4V", "AVI", "WMV", "FLV", "WebM", "TS"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 22) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Theme.accentStart.opacity(0.11))
                        .frame(width: 118, height: 118)
                    Image(systemName: "waveform")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(Theme.accentGradient)
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 34, height: 34)
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 2, y: 3)
                }

                VStack(spacing: 8) {
                    Text("把视频拖到这里")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("自动提取音轨并转换为高音质 MP3，支持批量处理")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        model.addFiles()
                    } label: {
                        Label("选择视频…", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityLabel("选择视频")

                    Button {
                        model.addFolder()
                    } label: {
                        Label("选择文件夹…", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityLabel("选择文件夹")
                }

                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(formats, id: \.self) { format in
                            Text(format)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.cardBackground))
                        }
                    }
                    Text("也支持其他 ffmpeg 可读取的视频格式")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 30) {
                    feature(icon: "waveform.badge.plus", title: "320 kbps 高保真")
                    feature(icon: "photo.on.rectangle", title: "智能封面")
                    feature(icon: "square.stack.3d.up", title: "批量并发")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 42)
            .frame(maxWidth: 660)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Theme.accentStart : Theme.separator.opacity(0.7),
                        style: StrokeStyle(lineWidth: isHighlighted ? 2 : 1.2, dash: [9, 7])
                    )
            )
            .padding(28)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Theme.accentStart.opacity(0.07), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 520
            )
        )
    }

    private func feature(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accentGradient)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
    }
}
