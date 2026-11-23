import SwiftUI

/// 音萃品牌 Logo（纯图形）。
/// 路径来自 backups/design/01_SVG矢量Logo/音萃_纯图形_透明_深色背景.svg，
/// 使用 SwiftUI Canvas 以矢量方式绘制，任意尺寸都保持清晰。
struct LogoMark: View {
    var size: CGFloat = 32

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 456
            let transform = CGAffineTransform(translationX: 8, y: 8)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))

            func fill(_ path: Path, _ color: Color) {
                context.fill(path.applying(transform), with: .color(color))
            }

            // 外层圆角方块（深色背景版本使用浅色主体）
            var body = Path()
            body.move(to: CGPoint(x: 104, y: 1))
            body.addLine(to: CGPoint(x: 324, y: 1))
            body.addCurve(to: CGPoint(x: 422, y: 102), control1: CGPoint(x: 382, y: 1), control2: CGPoint(x: 422, y: 45))
            body.addLine(to: CGPoint(x: 422, y: 246))
            body.addCurve(to: CGPoint(x: 232, y: 120), control1: CGPoint(x: 385, y: 210), control2: CGPoint(x: 355, y: 138))
            body.addCurve(to: CGPoint(x: 312, y: 193), control1: CGPoint(x: 306, y: 132), control2: CGPoint(x: 328, y: 157))
            body.addCurve(to: CGPoint(x: 205, y: 335), control1: CGPoint(x: 292, y: 239), control2: CGPoint(x: 209, y: 262))
            body.addLine(to: CGPoint(x: 104, y: 335))
            body.addCurve(to: CGPoint(x: 2, y: 236), control1: CGPoint(x: 47, y: 335), control2: CGPoint(x: 2, y: 292))
            body.addLine(to: CGPoint(x: 2, y: 103))
            body.addCurve(to: CGPoint(x: 104, y: 1), control1: CGPoint(x: 2, y: 47), control2: CGPoint(x: 46, y: 1))
            body.closeSubpath()
            fill(body, Theme.textPrimary)

            // 视频播放三角
            var play = Path()
            play.move(to: CGPoint(x: 99, y: 76))
            play.addCurve(to: CGPoint(x: 85, y: 73), control1: CGPoint(x: 92, y: 72), control2: CGPoint(x: 89, y: 72))
            play.addCurve(to: CGPoint(x: 74, y: 96), control1: CGPoint(x: 75, y: 76), control2: CGPoint(x: 74, y: 85))
            play.addLine(to: CGPoint(x: 74, y: 249))
            play.addCurve(to: CGPoint(x: 100, y: 271), control1: CGPoint(x: 74, y: 269), control2: CGPoint(x: 86, y: 279))
            play.addLine(to: CGPoint(x: 226, y: 191))
            play.addCurve(to: CGPoint(x: 226, y: 151), control1: CGPoint(x: 244, y: 180), control2: CGPoint(x: 244, y: 161))
            play.closeSubpath()
            fill(play, Theme.brandInk)

            // 萃绿音频水滴
            var drop = Path()
            drop.move(to: CGPoint(x: 337, y: 185))
            drop.addCurve(to: CGPoint(x: 263, y: 280), control1: CGPoint(x: 331, y: 227), control2: CGPoint(x: 296, y: 252))
            drop.addCurve(to: CGPoint(x: 232, y: 366), control1: CGPoint(x: 230, y: 307), control2: CGPoint(x: 224, y: 338))
            drop.addCurve(to: CGPoint(x: 326, y: 422), control1: CGPoint(x: 243, y: 405), control2: CGPoint(x: 282, y: 422))
            drop.addCurve(to: CGPoint(x: 430, y: 347), control1: CGPoint(x: 381, y: 422), control2: CGPoint(x: 421, y: 388))
            drop.addCurve(to: CGPoint(x: 388, y: 249), control1: CGPoint(x: 439, y: 310), control2: CGPoint(x: 421, y: 287))
            drop.addLine(to: CGPoint(x: 350, y: 202))
            drop.addCurve(to: CGPoint(x: 337, y: 185), control1: CGPoint(x: 345, y: 196), control2: CGPoint(x: 341, y: 187))
            drop.closeSubpath()
            fill(drop, Theme.brandPrimary)

            // 水滴内的五根白色声波
            let bars: [(x: CGFloat, y: CGFloat, height: CGFloat)] = [
                (267, 301, 41),
                (297, 286, 69),
                (327, 263, 115),
                (357, 286, 69),
                (387, 301, 41)
            ]
            for bar in bars {
                let rect = CGRect(x: bar.x, y: bar.y, width: 16, height: bar.height)
                fill(Path(roundedRect: rect, cornerRadius: 8), .white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("音萃 SoundDistill")
    }
}
