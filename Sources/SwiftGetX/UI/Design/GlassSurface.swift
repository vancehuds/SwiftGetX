import SwiftUI

struct MonochromeWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseColor

            LinearGradient(
                colors: [topEdgeTint, .clear],
                startPoint: .top,
                endPoint: .center
            )

            LinearGradient(
                colors: [.clear, bottomEdgeTint],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var baseColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var topEdgeTint: Color {
        colorScheme == .dark ? .white.opacity(0.035) : .black.opacity(0.025)
    }

    private var bottomEdgeTint: Color {
        colorScheme == .dark ? .white.opacity(0.018) : .black.opacity(0.016)
    }
}

struct GlassSurface<Content: View>: View {
    enum Level {
        case background
        case panel
        case floating
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.responsiveLayout) private var layout

    var level: Level = .panel
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(background)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay(alignment: .top) {
                if level != .background {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.22 : 0.58),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layout.value(cornerRadius), style: .continuous)
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            shape
                .fill(solidFallback)
        } else {
            shape
                .fill(material)
                .overlay {
                    shape.fill(surfaceTint)
                }
        }
    }

    private var material: Material {
        switch level {
        case .background:
            .thinMaterial
        case .panel:
            .thinMaterial
        case .floating:
            .regularMaterial
        }
    }

    private var solidFallback: Color {
        colorScheme == .dark
            ? Color.white.opacity(level == .floating ? 0.13 : 0.09)
            : Color.black.opacity(level == .floating ? 0.055 : 0.04)
    }

    private var surfaceTint: Color {
        switch (level, colorScheme) {
        case (.background, .dark): Color.white.opacity(0.03)
        case (.background, _): Color.white.opacity(0.62)
        case (.panel, .dark): Color.white.opacity(0.055)
        case (.panel, _): Color.white.opacity(0.70)
        case (.floating, .dark): Color.white.opacity(0.085)
        case (.floating, _): Color.white.opacity(0.78)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(level == .floating ? 0.22 : 0.15)
            : Color.black.opacity(level == .floating ? 0.14 : 0.10)
    }

    private var borderWidth: CGFloat {
        switch level {
        case .background: 0
        case .panel: 1
        case .floating: 1
        }
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(level == .floating ? 0.55 : 0.36)
            : Color.black.opacity(level == .floating ? 0.12 : 0.055)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .background: 0
        case .panel: layout.value(6)
        case .floating: layout.value(16)
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .background: 0
        case .panel: layout.value(1)
        case .floating: layout.value(6)
        }
    }
}

struct ContentSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.responsiveLayout) private var layout

    var isSelected = false
    var isHovered = false
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: layout.value(cornerRadius), style: .continuous)

        shape
            .fill(baseFill)
            .overlay {
                shape.fill(selectionFill)
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1)
            }
    }

    private var baseFill: Color {
        if reduceTransparency {
            return colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.black.opacity(0.045)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.035)
    }

    private var selectionFill: Color {
        if isSelected {
            return tint.opacity(colorScheme == .dark ? 0.22 : 0.13)
        }
        return Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.07 : 0.045) : 0)
    }

    private var borderColor: Color {
        if isSelected {
            return tint.opacity(colorScheme == .dark ? 0.42 : 0.34)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.075)
    }
}

struct GlassCellBackground: View {
    var isSelected = false
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 8

    @State private var isHovered = false

    var body: some View {
        ContentSurfaceBackground(
            isSelected: isSelected,
            isHovered: isHovered,
            tint: tint,
            cornerRadius: cornerRadius
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct LiquidProgressBar: View {
    var progress: Double
    var tint: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05), lineWidth: 0.5)
                    }

                Capsule()
                    .fill(tint)
                    .frame(width: max(width, progress > 0 ? layout.value(6) : 0))
            }
        }
        .frame(height: layout.value(6))
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
            .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            .background {
                if !reduceTransparency {
                    Circle()
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                Circle()
                    .fill(isPressed ? Color.primary.opacity(0.18) : Color.primary.opacity(isHovered ? 0.09 : 0.035))
            }
            .overlay {
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.responsiveLayout) private var layout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(layout.font(14, weight: .semibold))
            .frame(width: layout.value(34), height: layout.value(34))
            .background(
                GlassIconButtonBackground(isPressed: configuration.isPressed)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}
