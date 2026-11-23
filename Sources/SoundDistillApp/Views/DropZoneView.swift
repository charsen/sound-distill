import SwiftUI

struct DropZoneView: View {
    @EnvironmentObject private var model: AppModel
    let isHighlighted: Bool

    private let formats = ["MP4", "MKV", "MOV", "M4V", "AVI", "WMV", "FLV", "WebM", "TS"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 22) {
                LogoMark(size: 118)
                    .shadow(color: Theme.brandPrimary.opacity(0.22), radius: 26, y: 8)

                VStack(spacing: 8) {
                    Text("把视频拖到这里")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("自动提取音轨并转换为高音质 MP3，支持批量处理")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
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
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.control))
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.7))
                        }
                    }
                    Text("也支持其他 ffmpeg 可读取的视频格式")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
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
                    .fill(Theme.control.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Theme.brandPrimary : Theme.border,
                        style: StrokeStyle(lineWidth: isHighlighted ? 2 : 1.2, dash: [9, 7])
                    )
            )
            .padding(28)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Theme.brandPrimary.opacity(0.09), .clear],
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
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 110)
    }
}
