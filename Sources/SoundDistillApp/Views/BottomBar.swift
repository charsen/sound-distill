import SwiftUI

struct BottomBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            statusSummary

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                Text("MP3 · \(model.settings.quality.shortName)")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.cardBackground.opacity(0.8)))

            if model.completedCount > 0 {
                Button {
                    model.openOutputFolder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                }
                .buttonStyle(IconActionButtonStyle())
                .help("打开输出文件位置")
            }

            if model.isRunning {
                Button("取消") { model.cancelAll() }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .frame(width: 72)
            }

            Button(model.startButtonTitle) {
                model.startConversion()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .frame(width: 124)
            .disabled(!model.canStart)
            .accessibilityLabel(model.startButtonTitle)
            .opacity(model.canStart ? 1 : 0.55)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(.bar)
    }

    @ViewBuilder
    private var statusSummary: some View {
        if model.jobs.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("准备就绪")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        } else if model.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在转换 \(model.activeCount) 项，已完成 \(model.completedCount) / \(model.jobs.count)")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                Text("\(model.jobs.count) 个视频")
                    .font(.system(size: 11.5, weight: .medium))
                if model.queuedCount > 0 {
                    Text("\(model.queuedCount) 待转换")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if model.completedCount > 0 {
                    Text("\(model.completedCount) 已完成")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.16, green: 0.62, blue: 0.34))
                }
                if model.failedCount > 0 {
                    Text("\(model.failedCount) 失败")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
