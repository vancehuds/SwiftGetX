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
            .regularMaterial
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
        case (.background, .dark): Color.white.opacity(0.04)
        case (.background, _): Color.white.opacity(0.18)
        case (.panel, .dark): Color.white.opacity(0.06)
        case (.panel, _): Color.white.opacity(0.28)
        case (.floating, .dark): Color.white.opacity(0.08)
        case (.floating, _): Color.white.opacity(0.34)
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
            ? Color.black.opacity(level == .floating ? 0.22 : 0.14)
            : Color.black.opacity(level == .floating ? 0.08 : 0.05)
    }

    private var shadowRadius: CGFloat {
        switch level {
        case .background: 0
        case .panel: 8
        case .floating: 12
        }
    }

    private var shadowY: CGFloat {
        switch level {
        case .background: 0
        case .panel: 2
        case .floating: 6
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
                    .fill(isSelected ? tint.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            } else {
                shape
                    .fill(isSelected ? .regularMaterial : .thinMaterial)
            }

            shape
                .fill(
                    isSelected
                        ? tint.opacity(colorScheme == .dark ? 0.18 : 0.12)
                        : Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.07 : 0.045) : 0)
                )
        }
        .overlay {
            shape
                .strokeBorder(
                    isSelected ? tint.opacity(0.32) : borderColor,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
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
            .fill(reduceTransparency ? Color.primary.opacity(0.08) : Color.clear)
            .background {
                if !reduceTransparency {
                    Circle()
                        .fill(.thinMaterial)
                }
            }
            .overlay {
                Circle()
                    .fill(isPressed ? Color.primary.opacity(0.18) : Color.primary.opacity(isHovered ? 0.08 : 0.04))
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

