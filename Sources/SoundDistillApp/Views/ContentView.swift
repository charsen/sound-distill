import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderBar()
                Divider().opacity(0.6)

                if model.ffmpegStatus == .missing {
                    FFmpegMissingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        MainQueueArea(isDropTargeted: isDropTargeted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().opacity(0.6)
                        SettingsPanel()
                            .frame(width: 318)
                    }
                }

                Divider().opacity(0.6)
                BottomBar()
            }
            .background(Theme.background)

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ToastView(message: toast)
                        .padding(.bottom, 78)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.toast)
            }
        }
        .overlay {
            if isDropTargeted {
                DropOverlay()
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $model.showHelp) {
            HelpView()
                .environmentObject(model)
        }
        .sheet(item: $model.batchSummary) { summary in
            BatchSummaryView(summary: summary)
                .environmentObject(model)
        }
        // 统一关闭 macOS 默认的蓝色键盘对焦框，保留自定义边框与可聚焦能力。
        .focusEffectDisabled()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                if let url = object {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if urls.isEmpty {
                model.showToast("无法读取拖入的文件", kind: .warning)
            } else {
                model.add(urls: urls)
            }
        }
        return true
    }
}

private struct MainQueueArea: View {
    @EnvironmentObject private var model: AppModel
    let isDropTargeted: Bool

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                DropZoneView(isHighlighted: isDropTargeted)
            } else {
                QueueView()
            }
        }
        .background(Theme.background)
    }
}

struct HeaderBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            BrandMark(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("音萃 SoundDistill")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("视频 → 高音质 MP3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ffmpegBadge

            Button {
                model.showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("使用说明")
            .accessibilityLabel("使用说明")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Theme.background)
    }

    @ViewBuilder
    private var ffmpegBadge: some View {
        switch model.ffmpegStatus {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("检测 ffmpeg…")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Theme.cardBackground))
        case .available(let version):
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.15, green: 0.68, blue: 0.38)).frame(width: 6, height: 6)
                Text("ffmpeg \(version)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Theme.cardBackground))
        case .missing:
            Button {
                model.showHelp = true
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("ffmpeg 未安装")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.orange.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.accentGradient)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accentEnd.opacity(0.22), radius: 5, y: 2)
    }
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(message.text)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Theme.separator.opacity(0.5), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var iconName: String {
        switch message.kind {
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch message.kind {
        case .info: return Theme.accentStart
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.accentStart.opacity(0.06))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accentStart, style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Theme.accentGradient)
                Text("松开以添加视频")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(18)
    }
}
