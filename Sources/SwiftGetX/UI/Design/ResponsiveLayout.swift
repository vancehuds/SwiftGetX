import SwiftUI

struct ResponsiveLayout: Equatable {
    static let referenceSize = CGSize(width: 1080, height: 680)
    static let standard = ResponsiveLayout(scale: 1)

    let scale: CGFloat
    let fontScale: CGFloat

    init(windowSize: CGSize) {
        let widthScale = max(windowSize.width, 1) / Self.referenceSize.width
        let heightScale = max(windowSize.height, 1) / Self.referenceSize.height
        let resolvedScale = min(widthScale, heightScale).clamped(to: 0.66...1.28)

        scale = resolvedScale
        fontScale = resolvedScale.clamped(to: 0.78...1.20)
    }

    init(scale: CGFloat) {
        let resolvedScale = scale.clamped(to: 0.66...1.28)

        self.scale = resolvedScale
        fontScale = resolvedScale.clamped(to: 0.78...1.20)
    }

    func value(_ base: CGFloat) -> CGFloat {
        base * scale
    }

    func fontSize(_ base: CGFloat) -> CGFloat {
        base * fontScale
    }

    func font(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design = .default) -> Font {
        .system(size: fontSize(size), weight: weight, design: design)
    }
}

private struct ResponsiveLayoutKey: EnvironmentKey {
    static let defaultValue = ResponsiveLayout.standard
}

extension EnvironmentValues {
    var responsiveLayout: ResponsiveLayout {
        get { self[ResponsiveLayoutKey.self] }
        set { self[ResponsiveLayoutKey.self] = newValue }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
