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
            .clipShape(shape)
            .overlay(liquidRim)
            .overlay {
                shape
                    .strokeBorder(borderStyle, lineWidth: borderWidth)
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            shape
                .fill(solidFallback)
        } else {
            ZStack {
                shape
                    .fill(material)
                liquidFill
            }
        }
    }

    private var material: Material {
        switch level {
        case .background:
            .ultraThinMaterial
        case .panel:
            .regularMaterial
        case .floating:
            .thickMaterial
        }
    }

    private var solidFallback: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var liquidFill: some View {
        ZStack {
            LinearGradient(
                colors: fillColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.22 : 0.56),
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.cyan.opacity(colorScheme == .dark ? 0.05 : 0.09),
                    Color.blue.opacity(colorScheme == .dark ? 0.08 : 0.06)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.16 : 0.055)
                ],
                startPoint: .center,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(shape)
    }

    private var fillColors: [Color] {
        switch (level, colorScheme) {
        case (.background, .dark):
            [
                Color.white.opacity(0.06),
                Color.white.opacity(0.03),
                Color.black.opacity(0.12)
            ]
        case (.background, _):
            [
                Color.white.opacity(0.28),
                Color.white.opacity(0.13),
                Color.black.opacity(0.025)
            ]
        case (.panel, .dark):
            [
                Color.white.opacity(0.16),
                Color.white.opacity(0.07),
                Color.black.opacity(0.18)
            ]
        case (.panel, _):
            [
                Color.white.opacity(0.48),
                Color.white.opacity(0.22),
                Color.black.opacity(0.04)
            ]
        case (.floating, .dark):
            [
                Color.white.opacity(0.23),
                Color.white.opacity(0.11),
                Color.black.opacity(0.14)
            ]
        case (.floating, _):
            [
                Color.white.opacity(0.64),
                Color.white.opacity(0.30),
                Color.black.opacity(0.035)
            ]
        }
    }

    private var liquidRim: some View {
        ZStack {
            shape
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.72), lineWidth: 1.2)
                .blur(radius: 0.35)
                .offset(x: -0.35, y: -0.35)
                .mask(shape)
            shape
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.10), lineWidth: 1)
                .blur(radius: 3.5)
                .offset(y: 2.2)
                .mask(shape)
        }
        .opacity(reduceTransparency ? 0 : 1)
    }

    private var borderStyle: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.40 : 0.86),
                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.48),
                Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderWidth: CGFloat {
        switch level {
        case .background: 0.7
        case .panel: 1.0
        case .floating: 1.15
        }
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(level == .floating ? 0.42 : 0.30)
            : Color.black.opacity(level == .floating ? 0.16 : 0.09)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .background: 0
        case .panel: 14
        case .floating: 22
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .background: 0
        case .panel: 6
        case .floating: 12
        }
    }
}

struct GlassCellBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var isSelected = false
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape
                    .fill(.thinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.32),
                        Color.white.opacity(colorScheme == .dark ? 0.035 : 0.14),
                        Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)
            }

            shape
                .fill(isSelected ? tint.opacity(colorScheme == .dark ? 0.24 : 0.18) : Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.045))
        }
        .overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.64),
                            isSelected ? tint.opacity(0.48) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22),
                            Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.1 : 0.8
                )
        }
    }
}

struct LiquidProgressBar: View {
    var progress: Double
    var tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.08))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.13 : 0.50), lineWidth: 0.7)
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.62),
                                tint,
                                .white.opacity(colorScheme == .dark ? 0.36 : 0.56)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, progress > 0 ? 8 : 0))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.34))
                            .frame(height: 2)
                            .padding(.horizontal, 3)
                    }
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.48 : 0.68))
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(reduceTransparency ? Color.primary.opacity(0.10) : Color.clear)
                    .background {
                        if !reduceTransparency {
                            Circle()
                                .fill(.thinMaterial)
                        }
                    }
                    .overlay {
                        Circle()
                            .fill(configuration.isPressed ? Color.primary.opacity(0.18) : Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.045))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.58), lineWidth: 0.8)
                    }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}
