import SwiftUI

enum XmacTheme {
    static let indigo = Color(red: 0.12, green: 0.24, blue: 0.82)
    static let blue = Color(red: 0.08, green: 0.48, blue: 0.98)
    static let cyan = Color(red: 0.14, green: 0.78, blue: 0.98)
    static let violet = Color(red: 0.47, green: 0.30, blue: 0.98)
    static let navy = Color(red: 0.025, green: 0.055, blue: 0.18)

    static let sidebarGradient = LinearGradient(
        colors: [
            Color(red: 0.025, green: 0.06, blue: 0.22),
            Color(red: 0.055, green: 0.10, blue: 0.36),
            Color(red: 0.075, green: 0.08, blue: 0.27)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradient = LinearGradient(
        colors: [blue, indigo, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let workspaceBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.035, green: 0.047, blue: 0.085, alpha: 1)
            : NSColor(srgbRed: 0.955, green: 0.97, blue: 0.995, alpha: 1)
    })

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.07, green: 0.085, blue: 0.14, alpha: 0.92)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.88)
    })

    static let cardStroke = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.28, green: 0.38, blue: 0.7, alpha: 0.28)
            : NSColor(srgbRed: 0.17, green: 0.32, blue: 0.7, alpha: 0.12)
    })
}

private final class PageEntranceState: ObservableObject {
    @Published var isVisible = false
}

private struct XmacPageModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var entrance = PageEntranceState()

    func body(content: Content) -> some View {
        content
            .background(XmacTheme.workspaceBackground.ignoresSafeArea())
            .opacity(entrance.isVisible || reduceMotion ? 1 : 0)
            .offset(y: entrance.isVisible || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: entrance.isVisible)
            .onAppear {
                entrance.isVisible = true
            }
    }
}

extension View {
    func xmacPage() -> some View {
        modifier(XmacPageModifier())
    }
}

public struct ModernCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(XmacTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(XmacTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: XmacTheme.navy.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

public struct BrandPageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let trailing: Trailing

    public init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(XmacTheme.blue)
                }
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            trailing
        }
    }
}

public struct BrandSectionTitle: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

public struct BrandIconTile: View {
    let iconName: String
    let color: Color
    let size: CGFloat

    public init(
        iconName: String,
        color: Color = Color(red: 0.08, green: 0.48, blue: 0.98),
        size: CGFloat = 42
    ) {
        self.iconName = iconName
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .stroke(color.opacity(0.16), lineWidth: 1)
            )
    }
}

public struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XmacTheme.brandGradient)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.34)
            )
            .shadow(
                color: XmacTheme.blue.opacity(isEnabled ? (configuration.isPressed ? 0.12 : 0.24) : 0),
                radius: 8,
                y: 4
            )
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEnabled)
    }
}

public struct BrandSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(
                isEnabled
                    ? (configuration.isPressed ? XmacTheme.indigo : XmacTheme.blue)
                    : Color.secondary.opacity(0.62)
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isEnabled
                            ? XmacTheme.blue.opacity(configuration.isPressed ? 0.16 : 0.08)
                            : Color.secondary.opacity(0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isEnabled ? XmacTheme.blue.opacity(0.18) : Color.secondary.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEnabled)
    }
}

public struct BrandDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isEnabled ? Color.red : Color.secondary.opacity(0.62))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? Color.red.opacity(configuration.isPressed ? 0.16 : 0.08) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isEnabled ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEnabled)
    }
}

public struct BrandTextField: View {
    let prompt: String
    @Binding var text: String
    let accessibilityLabel: String?
    @FocusState private var isFocused: Bool

    public init(_ prompt: String, text: Binding<String>, accessibilityLabel: String? = nil) {
        self.prompt = prompt
        self._text = text
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XmacTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? XmacTheme.blue.opacity(0.72) : XmacTheme.cardStroke, lineWidth: isFocused ? 1.5 : 1)
            )
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel ?? prompt)
    }
}

public struct BrandToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(XmacTheme.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct BrandListRow<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
    }
}

public struct StatusBadge: View {
    let title: String
    let isPositive: Bool

    public init(title: String, isPositive: Bool) {
        self.title = title
        self.isPositive = isPositive
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isPositive ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: (isPositive ? Color.green : Color.orange).opacity(0.4), radius: 4)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isPositive ? .green : .orange)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill((isPositive ? Color.green : Color.orange).opacity(0.1)))
        .overlay(Capsule().stroke((isPositive ? Color.green : Color.orange).opacity(0.18), lineWidth: 1))
    }
}

public struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let iconName: String
    let accentColor: Color

    public init(title: String, value: String, subtitle: String, iconName: String, accentColor: Color) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.iconName = iconName
        self.accentColor = accentColor
    }

    public var body: some View {
        ModernCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                BrandIconTile(iconName: iconName, color: accentColor, size: 46)
            }
        }
    }
}

public struct BrandKeycap: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(XmacTheme.blue)
            .frame(minWidth: 46)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(XmacTheme.blue.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(XmacTheme.blue.opacity(0.18), lineWidth: 1))
    }
}
