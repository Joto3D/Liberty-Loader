import SwiftUI

// Super Earth palette: near-black panels with the signature yellow.
extension Color {
    static let hdYellow = Color(red: 1.0, green: 0.906, blue: 0.122)
    static let hdBackground = Color(red: 0.050, green: 0.055, blue: 0.063)
    static let hdPanel = Color(red: 0.086, green: 0.094, blue: 0.106)
    static let hdPanelRaised = Color(red: 0.122, green: 0.130, blue: 0.145)
    static let hdBorder = Color.white.opacity(0.08)
    static let hdText = Color.white.opacity(0.92)
    static let hdMuted = Color.white.opacity(0.55)
    static let hdDanger = Color(red: 0.96, green: 0.32, blue: 0.26)
    static let hdSuccess = Color(red: 0.38, green: 0.86, blue: 0.47)
    static let hdInfo = Color(red: 0.36, green: 0.70, blue: 1.0)
    static let hdWarning = Color(red: 1.0, green: 0.62, blue: 0.18)
}

extension Font {
    /// Heavy condensed headline, military-stencil feel.
    static func hdDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Small monospaced "terminal" label.
    static func hdLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

enum HDMetrics {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cut: CGFloat = 14
}
