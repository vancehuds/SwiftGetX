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
            .overlay(
                // Bottom-right dark refractive border
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth * 1.5
                    )
                    .blendMode(.multiply)
                    .mask(shape)
            )
            .overlay(
                // Specular highlight rim (top-left)
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.58 : 0.88),
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        ),
                        lineWidth: borderWidth * 1.2
                    )
                    .blendMode(.screen)
                    .mask(shape)
            )
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

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape
                    .fill(isSelected ? tint.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            } else {
                shape
                    .fill(isSelected ? .regularMaterial : (isHovered ? .regularMaterial : .thinMaterial))
                
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.38),
                        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.18),
                        Color.black.opacity(colorScheme == .dark ? 0.10 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)
            }

            // Glow layer
            shape
                .fill(
                    isSelected 
                        ? tint.opacity(colorScheme == .dark ? 0.26 : 0.20) 
                        : (isHovered ? tint.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.045))
                )
        }
        .overlay {
            // Specular border highlights
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? (isHovered ? 0.40 : 0.25) : (isHovered ? 0.85 : 0.68)),
                            isSelected ? tint.opacity(0.60) : (isHovered ? tint.opacity(0.24) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22)),
                            Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.25 : (isHovered ? 1.0 : 0.8)
                )
        }
        .scaleEffect(isHovered && !isSelected ? 1.015 : 1.0)
        .shadow(
            color: isSelected 
                ? tint.opacity(colorScheme == .dark ? 0.18 : 0.12)
                : (isHovered ? Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06) : Color.clear),
            radius: isSelected ? 8 : (isHovered ? 6 : 0),
            x: 0,
            y: isSelected ? 3 : (isHovered ? 2 : 0)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct LiquidProgressBar: View {
    var progress: Double
    var tint: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var shineOffset: CGFloat = -1.0

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
                                tint.opacity(0.70),
                                tint,
                                tint.opacity(0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, progress > 0 ? 8 : 0))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.38))
                            .frame(height: 2)
                            .padding(.horizontal, 3)
                    }
                    .overlay(
                        GeometryReader { fillProxy in
                            let fillWidth = fillProxy.size.width
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.48), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 60)
                            .offset(x: fillWidth * shineOffset)
                        }
                        .mask(Capsule())
                    )
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.60 : 0.85))
                            .frame(width: 8, height: 8)
                            .blur(radius: 2)
                            .offset(x: -1)
                            .shadow(color: tint, radius: 4)
                    }
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    shineOffset = 1.5
                }
            }
        }
        .frame(height: 8)
        .accessibilityLabel("下载进度")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct GlassIconButtonBackground: View {
    let isPressed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(reduceTransparency ? Color.primary.opacity(0.10) : Color.clear)
            .background {
                if !reduceTransparency {
                    Circle()
                        .fill(isHovered ? .regularMaterial : .thinMaterial)
                }
            }
            .overlay {
                Circle()
                    .fill(isPressed ? Color.primary.opacity(0.22) : (isHovered ? Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.045)))
            }
            .overlay {
                if isHovered && !reduceTransparency {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.65),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                        .blur(radius: 0.2)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? (isHovered ? 0.36 : 0.16) : (isHovered ? 0.78 : 0.58)), lineWidth: 0.8)
            }
            .scaleEffect(isPressed ? 0.94 : (isHovered ? 1.06 : 1.0))
            .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.04), radius: isHovered ? 4 : 1, y: isHovered ? 2 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
            .animation(.interactiveSpring, value: isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(
                GlassIconButtonBackground(isPressed: configuration.isPressed)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}
