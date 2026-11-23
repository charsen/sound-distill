import SwiftUI
import SoundDistillCore

struct SettingsPanel: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("转换设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                qualitySection
                coverSection
                outputSection
                fileSection
                performanceSection

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                    Text("由 ffmpeg + LAME 编码")
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(18)
        }
        .background(Theme.sidebar)
        .focusEffectDisabled()
    }

    // MARK: - 音质

    private var qualitySection: some View {
        SettingsSection(title: "音质") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MP3Quality.allCases) { quality in
                    let selected = model.settings.quality == quality
                    Button {
                        model.settings.quality = quality
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quality.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selected ? Theme.brandPrimary : Theme.textPrimary)
                            Text(qualityTagline(quality))
                                .font(.system(size: 9))
                                .foregroundStyle(selected ? Theme.textSecondary : Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? Theme.selected : Theme.control)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(selected ? Theme.brandPrimary.opacity(0.85) : Theme.border, lineWidth: selected ? 1.2 : 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("音质 \(quality.shortName)")
                    .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }
            Text(model.settings.quality.detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qualityTagline(_ quality: MP3Quality) -> String {
        switch quality {
        case .cbr320: return "最高固定码率"
        case .vbrV0:  return "最高可变码率"
        case .cbr256: return "高音质"
        case .cbr192: return "日常标准"
        }
    }

    // MARK: - 封面

    private var coverSection: some View {
        SettingsSection(title: "封面") {
            ThemedSegmentedControl(
                options: [
                    .init(value: CoverPolicy.smart, label: "智能"),
                    .init(value: CoverPolicy.frameOnly, label: "截取画面"),
                    .init(value: CoverPolicy.none, label: "无")
                ],
                selection: $model.settings.coverPolicy
            )
            .accessibilityLabel("封面策略")

            Text(model.settings.coverPolicy.detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 输出

    private var outputSection: some View {
        SettingsSection(title: "输出位置") {
            Toggle(isOn: Binding(
                get: { model.settings.useCustomOutput },
                set: { newValue in
                    if newValue {
                        model.enableCustomOutput()
                    } else {
                        model.settings.useCustomOutput = false
                    }
                }
            )) {
                Text("输出到指定文件夹")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.brandPrimary)

            if model.settings.useCustomOutput {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.settings.customOutputPath.isEmpty ? "未选择（将使用视频所在文件夹）" : model.settings.customOutputPath)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("选择…") { model.chooseOutputFolder() }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brandPrimary)
                        .accessibilityLabel("选择输出文件夹")
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.7))

                Toggle(isOn: $model.settings.preserveFolderStructure) {
                    Text("保持原目录结构")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.brandPrimary)

                Text("按导入文件夹的层级创建子目录，避免多个视频的同名 MP3 混在一起。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 文件

    private var fileSection: some View {
        SettingsSection(title: "文件") {
            HStack {
                Text("同名文件")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Button {
                            model.settings.conflictPolicy = policy
                        } label: {
                            HStack {
                                Text(policy.displayName)
                                if model.settings.conflictPolicy == policy {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(model.settings.conflictPolicy.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.7))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("同名文件处理")
            }

            Toggle(isOn: $model.settings.preserveMetadata) {
                Text("复制视频元数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.brandPrimary)

            Text(model.settings.conflictPolicy.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 性能

    private var performanceSection: some View {
        SettingsSection(title: "性能") {
            HStack {
                Text("同时转换")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Stepper("", value: $model.settings.concurrency, in: 1...8)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("同时转换数量")
                Text("\(model.settings.concurrency) 个")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, alignment: .trailing)
            }

            Toggle(isOn: $model.settings.playSoundOnFinish) {
                Text("完成后提示音")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.brandPrimary)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .kerning(0.4)
            content
        }
    }
}
