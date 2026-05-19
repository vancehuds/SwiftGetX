import SwiftUI

struct GlassSurface<Content: View>: View {
    enum Level {
        case background
        case panel
        case floating
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var level: Level = .panel
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            solidFallback
        } else {
            ZStack {
                Rectangle()
                    .fill(material)
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34),
                        Color.white.opacity(0.04),
                        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var material: Material {
        switch level {
        case .background:
            .regularMaterial
        case .panel:
            .thickMaterial
        case .floating:
            .ultraThickMaterial
        }
    }

    private var solidFallback: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.62)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.38)
            : Color.black.opacity(0.12)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .background: 0
        case .panel: 16
        case .floating: 26
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .background: 0
        case .panel: 8
        case .floating: 16
        }
    }
}

struct LiquidProgressBar: View {
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.7),
                                tint,
                                .white.opacity(0.45)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, progress > 0 ? 8 : 0))
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white.opacity(0.58))
                            .frame(width: 8, height: 8)
                            .blur(radius: 3)
                            .offset(x: -2)
                    }
            }
        }
        .frame(height: 8)
        .accessibilityLabel("下载进度")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(configuration.isPressed ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08))
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}
