import SwiftUI

extension Color {
    /// 用 0xRRGGBB 构造颜色，便于与设计稿中的色值一一对应。
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// 音萃 V3 深色主题色板。
/// 色值来源：backups/design/04_配色文件/sounddistill-colors.css。
/// 只替换颜色，不改变界面布局、控件尺寸与 Logo。
enum Theme {
    // MARK: - 品牌色

    static let brandPrimary = Color(hex: 0x099582)
    static let brandPrimaryAction = Color(hex: 0x067566)
    static let brandPrimaryHover = Color(hex: 0x099582)
    static let brandInk = Color(hex: 0x171B1D)

    // MARK: - 深色表面

    /// 窗口背景
    static let window = Color(hex: 0x171B1D)
    /// 工具栏 / 顶栏 / 底栏
    static let toolbar = Color(hex: 0x22292B)
    /// 设置面板 / 侧栏
    static let sidebar = Color(hex: 0x252C2E)
    /// 控件 / 卡片背景
    static let control = Color(hex: 0x1C2224)
    /// 边框 / 分割线
    static let border = Color(hex: 0x394345)
    /// 选中背景
    static let selected = Color(hex: 0x183C37)
    /// 悬停背景
    static let hover = Color(hex: 0x2C3436)

    static let textPrimary = Color(hex: 0xF2F5F4)
    static let textSecondary = Color(hex: 0xA4B1AF)
    static let textTertiary = Color(hex: 0x778482)

    // MARK: - 状态色（按深色底校正亮度，保持同一色相）

    static let success = Color(hex: 0x3ECF8E)
    static let warning = Color(hex: 0xE8B45A)
    static let danger = Color(hex: 0xF0706B)

    /// 品牌图标的轻微渐变（仅用于 Logo/装饰图标，不用于大面积背景）。
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [brandPrimary, brandPrimaryAction],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryActionButtonBody(configuration: configuration, fullWidth: fullWidth)
    }
}

private struct PrimaryActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Theme.brandPrimaryAction
                            : (isHovered ? Theme.brandPrimaryHover : Theme.brandPrimaryAction)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.brandPrimaryHover.opacity(isHovered ? 0.55 : 0), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryActionButtonBody(configuration: configuration)
    }
}

private struct SecondaryActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Theme.selected : (isHovered ? Theme.hover : Theme.control))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(configuration.isPressed || isHovered ? Theme.brandPrimary.opacity(0.55) : Theme.border, lineWidth: 0.8)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct IconActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconActionButtonBody(configuration: configuration)
    }
}

private struct IconActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovered ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed || isHovered ? Theme.hover : .clear)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// 深色主题的分段选择器：选中项使用设计稿的「选中背景 + 品牌绿描边」。
/// 外形尺寸与系统 segmented Picker 一致，仅替换颜色。
struct ThemedSegmentedControl<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Theme.brandPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selection == option.value ? Theme.selected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(selection == option.value ? Theme.brandPrimary.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.8)
        )
    }
}

/// 深色主题的线性进度条：轨道使用边框色，进度使用品牌绿。
/// 尺寸与系统 ProgressView(.linear) 保持一致，不改变原有布局。
struct ThemedProgressBar: View {
    let value: Double
    var tint: Color = Theme.brandPrimary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border.opacity(0.55))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * min(max(value, 0), 1)))
            }
        }
    }
}
