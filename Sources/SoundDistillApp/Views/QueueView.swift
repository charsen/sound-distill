import SwiftUI
import SoundDistillCore

struct QueueView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("任务队列")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(model.jobs.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.cardBackground))

                Spacer()

                Menu {
                    Button("添加视频…") { model.addFiles() }
                    Button("添加文件夹…") { model.addFolder() }
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isRunning)
                .accessibilityLabel("添加视频")

                if model.jobs.contains(where: { $0.status.isFinished }) {
                    Button("清空已完成") {
                        model.clearFinished()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(model.isRunning)
                    .accessibilityLabel("清空已完成")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 46)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.jobs) { job in
                        JobRowView(job: job)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.automatic)

            if model.isRunning {
                HStack(spacing: 12) {
                    ProgressView(value: model.overallProgress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accentStart)
                        .frame(maxWidth: 260)
                    Text("正在处理 \(model.activeCount) 个任务")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(model.overallProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accentStart)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.cardBackground.opacity(0.5))
            }
        }
    }
}

struct JobRowView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var job: JobItem

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if job.info?.hasEmbeddedCover == true, job.status != .completed {
                        Text("封面")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.accentStart)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accentStart.opacity(0.1)))
                    }
                    if job.hasMultipleAudioTracks,
                       job.status == .queued || job.status == .failed || job.status == .cancelled {
                        Menu {
                            ForEach(job.audioStreams, id: \.index) { stream in
                                Button {
                                    model.selectAudioStream(stream.index, for: job)
                                } label: {
                                    HStack {
                                        Text(stream.displayLabel)
                                        if job.selectedAudioStream?.index == stream.index {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("音轨", systemImage: "waveform")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Theme.accentStart)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("选择音轨")
                    }
                }

                Text(job.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if job.status.isActive {
                    HStack(spacing: 8) {
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                            .tint(job.status == .probing ? Color.orange : Theme.accentStart)
                            .frame(width: 170, height: 4)
                        Text(job.stageText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }

                if let subtitle = job.completionSubtitle, job.status == .completed {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if job.status == .completed, let warning = job.warningText {
                    Text(warning)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                if job.status == .failed, let error = job.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.22))
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 4)

            trailingActions
                .disabled(model.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(job.status == .completed ? Color.green.opacity(0.045) : Theme.cardBackground.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.separator.opacity(0.45), lineWidth: 0.7)
        )
        .contextMenu {
            if job.status == .completed {
                Button("在 Finder 中显示") { model.reveal(job) }
            }
            if job.status == .failed || job.status == .cancelled {
                Button("重试") { model.retry(job) }
            }
            if !job.status.isActive {
                Divider()
                Button("从列表移除", role: .destructive) { model.remove(job) }
            }
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(job.status.tint.opacity(0.1))
                .frame(width: 30, height: 30)
            if job.status.isActive || job.isProbingDetails {
                ProgressView()
                    .controlSize(.small)
                    .tint(job.status.tint)
            } else {
                Image(systemName: job.status.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(job.status.tint)
            }
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        switch job.status {
        case .queued:
            Button { model.remove(job) } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconActionButtonStyle())
            .help("从列表移除")
            .accessibilityLabel("从列表移除")
        case .probing, .converting:
            Text("\(Int(job.progress * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accentStart)
                .frame(width: 42, alignment: .trailing)
        case .completed:
            HStack(spacing: 4) {
                Button { model.reveal(job) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("在 Finder 中显示")
                .accessibilityLabel("在 Finder 中显示")

                Button { model.remove(job) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("从列表移除")
            }
        case .failed:
            HStack(spacing: 4) {
                Button("重试") { model.retry(job) }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentStart)
                Button { model.remove(job) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconActionButtonStyle())
                .help("从列表移除")
            }
        case .cancelled, .skipped:
            Button { model.remove(job) } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconActionButtonStyle())
            .help("从列表移除")
            .accessibilityLabel("从列表移除")
        }
    }
}
