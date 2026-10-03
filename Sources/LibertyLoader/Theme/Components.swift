import SwiftUI

/// Rectangle with the top-right corner clipped off, like Helldivers UI panels.
struct CutCornerShape: Shape {
    var cut: CGFloat = HDMetrics.cut

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Dark card used for every section. An accent colour adds a coloured edge and border.
struct HDPanel<Content: View>: View {
    var accent: Color?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hdPanel, in: CutCornerShape())
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle().fill(accent).frame(width: 3).padding(.vertical, 1)
                }
            }
            .overlay(CutCornerShape().stroke(accent?.opacity(0.45) ?? Color.hdBorder, lineWidth: 1))
    }
}

struct HDSectionHeader: View {
    let title: LocalizedStringKey
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.hdYellow).frame(width: 4, height: 14)
            Text(title)
                .font(.hdLabel(12))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.hdMuted)
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct HDPageTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.hdDisplay(34))
                .textCase(.uppercase)
                .foregroundStyle(Color.hdText)
            Text(subtitle)
                .foregroundStyle(Color.hdMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Big yellow call-to-action.
struct HDPrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hdDisplay(large ? 22 : 15))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Color.black.opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, large ? 30 : 18)
            .padding(.vertical, large ? 14 : 9)
            .background(
                Color.hdYellow.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                in: CutCornerShape(cut: large ? 14 : 9)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Outlined secondary action; pass `.hdDanger` for destructive ones.
struct HDSecondaryButtonStyle: ButtonStyle {
    var color: Color = .hdText
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.04), in: CutCornerShape(cut: 8))
            .overlay(CutCornerShape(cut: 8).stroke(color.opacity(isEnabled ? 0.45 : 0.15), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Diagonal yellow/black warning stripes.
struct HazardStripe: View {
    var stripeWidth: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            var x = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + stripeWidth, y: size.height))
                stripe.addLine(to: CGPoint(x: x + stripeWidth + size.height, y: 0))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(.hdYellow))
                x += stripeWidth * 2
            }
        }
    }
}

struct StatusPill: View {
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(text)
                .font(.hdLabel(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatTile: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HDPanel(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.hdYellow)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.hdLabel(10))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hdMuted)
                    Text(verbatim: value)
                        .font(.hdDisplay(22))
                        .foregroundStyle(Color.hdText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

/// Notice with an icon, title, message and optional actions.
struct HDBanner<Actions: View>: View {
    let icon: String
    let color: Color
    let title: Text
    var message: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        HDPanel(accent: color) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 6) {
                    title.font(.headline).foregroundStyle(Color.hdText)
                    if let message {
                        message.font(.callout).foregroundStyle(Color.hdMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) { actions }
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

extension HDBanner where Actions == EmptyView {
    init(icon: String, color: Color, title: Text, message: Text? = nil) {
        self.init(icon: icon, color: color, title: title, message: message) { EmptyView() }
    }
}

/// Selectable filter chip.
struct HDChip: View {
    let title: LocalizedStringKey
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.hdLabel(10))
                        .padding(.horizontal, 5)
                        .background(Color.black.opacity(0.25), in: Capsule())
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black : Color.hdText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.hdYellow : Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Coloured tag such as "RECOMMENDED" or "UPDATE".
struct HDTag: View {
    let text: LocalizedStringKey
    var color: Color = .hdYellow

    var body: some View {
        Text(text)
            .font(.hdLabel(9))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.6), lineWidth: 1))
    }
}

/// Page scaffold: dark background, scrollable column with consistent padding.
struct HDPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDMetrics.sectionSpacing) {
                content
            }
            .padding(HDMetrics.pagePadding)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.hdBackground)
    }
}
