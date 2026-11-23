import SwiftUI

struct BatchSummaryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let summary: BatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(summary.hasIssues ? Theme.warning.opacity(0.14) : Theme.brandPrimary.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: summary.hasIssues ? "exclamationmark" : "checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(summary.hasIssues ? Theme.warning : Theme.brandPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.hasIssues ? "本批有未完成项" : "本批转换完成")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("用时 \(formatDuration(summary.elapsed)) · 输出 \(summary.outputs.count) 个 MP3")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(SecondaryActionButtonStyle())
            }

            HStack(spacing: 10) {
                statCard(title: "成功", value: summary.completed, color: Theme.success)
                statCard(title: "失败", value: summary.failed, color: Theme.danger)
                statCard(title: "跳过", value: summary.skipped, color: Theme.warning)
                statCard(title: "取消", value: summary.cancelled, color: Theme.textSecondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(Theme.textSecondary)
                Text("本批输出总大小 \(JobItem.formatBytes(summary.outputBytes))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 0.7))

            if summary.hasIssues {
                Text("失败项会保留在队列中，可回到主窗口选择音轨后重试；跳过项表示同名输出已存在。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("在 Finder 中打开输出") {
                    model.openOutputFolder()
                    dismiss()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                Spacer()
                Button("继续转换") { dismiss() }
                    .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.window)
        .focusEffectDisabled()
    }

    private func statCard(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.7))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "不到 1 秒" }
        if seconds < 60 { return String(format: "%.1f 秒", seconds) }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes) 分 \(remainder) 秒"
    }
}
