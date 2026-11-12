import SwiftUI

/// Minimal logo mark — two plates connected by a bar, with
/// an optional hand-drawn underline arc for the editorial wordmark.
struct LogoMark: View {
    var size: CGFloat = 48
    var tint: Color = Palette.primary

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let plateRadius = h * 0.42
            let plateY = h / 2
            let leftCenter = CGPoint(x: w * 0.22, y: plateY)
            let rightCenter = CGPoint(x: w * 0.78, y: plateY)
            let barHeight = h * 0.16
            let barRect = CGRect(
                x: leftCenter.x,
                y: plateY - barHeight / 2,
                width: rightCenter.x - leftCenter.x,
                height: barHeight
            )

            // Bar.
            ctx.fill(
                Path(roundedRect: barRect, cornerRadius: barHeight / 2),
                with: .color(tint.opacity(0.55))
            )

            // Plates.
            for center in [leftCenter, rightCenter] {
                let rect = CGRect(
                    x: center.x - plateRadius,
                    y: center.y - plateRadius,
                    width: plateRadius * 2,
                    height: plateRadius * 2
                )
                ctx.fill(Circle().path(in: rect), with: .color(tint))
            }
        }
        .frame(width: size * 2, height: size)
    }
}

/// Full wordmark with hand-drawn underline arc — used on splash, onboarding.
struct AppMark: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            LogoMark(size: 32, tint: Palette.primaryDeep)
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("echo")
                        .font(Typography.display)
                        .foregroundStyle(Palette.ink)
                    Text(".r2")
                        .font(Typography.mono)
                        .foregroundStyle(Palette.primaryDeep)
                }
                HandDrawnUnderline()
                    .stroke(Palette.primaryDeep.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .frame(width: 110, height: 6)
            }
        }
    }
}

/// A wobbly hand-drawn arc — soft signature beneath the wordmark.
struct HandDrawnUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: mid + 1.5))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: mid + 1.5),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: mid - 2.5),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: mid + 4.0)
        )
        return p
    }
}
