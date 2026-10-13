import SwiftUI

public struct ModernCard<Content: View>: View {
    let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
        HStack(spacing: 5) {
            Circle()
                .fill(isPositive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isPositive ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isPositive ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
        )
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(accentColor)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.12))
                    )
            }
        }
    }
}
