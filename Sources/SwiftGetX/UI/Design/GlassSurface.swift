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
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: borderWidth)
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
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var surfaceTint: Color {
        switch (level, colorScheme) {
        case (.background, .dark): Color.white.opacity(0.02)
        case (.background, _): Color.white.opacity(0.10)
        case (.panel, .dark): Color.white.opacity(0.035)
        case (.panel, _): Color.white.opacity(0.18)
        case (.floating, .dark): Color.white.opacity(0.07)
        case (.floating, _): Color.white.opacity(0.30)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
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
            ? Color.black.opacity(level == .floating ? 0.24 : 0.10)
            : Color.black.opacity(level == .floating ? 0.10 : 0.045)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .background: 0
        case .panel: 6
        case .floating: 16
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .background: 0
        case .panel: 1
        case .floating: 6
        }
    }
}

struct ContentSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isSelected = false
    var isHovered = false
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
            return Color(nsColor: .controlBackgroundColor)
        }

        return colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.72)
            : Color(nsColor: .controlBackgroundColor).opacity(0.82)
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
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
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
                    .frame(width: max(width, progress > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
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
