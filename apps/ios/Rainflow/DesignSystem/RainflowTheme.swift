import SwiftUI
import UIKit

public enum RainflowColor {
    public static let background = adaptive(light: 0xF4F7F8, dark: 0x071014)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x10191D)
    public static let surfaceElevated = adaptive(light: 0xEAF0F2, dark: 0x162126)
    public static let border = adaptive(light: 0xD8E1E5, dark: 0x26343A)
    public static let textPrimary = adaptive(light: 0x102026, dark: 0xF4F8FA)
    public static let textSecondary = adaptive(light: 0x5E6F77, dark: 0x94A3AA)
    public static let brand = Color(hex: 0x1E8DFF)
    public static let brandAccent = Color(hex: 0x12C6D7)
    public static let income = Color(hex: 0x20A978)
    public static let expense = Color(hex: 0xE94F57)
    public static let warning = Color(hex: 0xE59A13)

    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct FinanceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RainflowColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(RainflowColor.border.opacity(0.72), lineWidth: 1)
            }
    }
}

struct ScreenHeader: View {
    let title: String
    var trailingSymbol: String?
    var trailingAccessibilityLabel = "More actions"
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundStyle(RainflowColor.brandAccent)
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            if let trailingSymbol, let trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: trailingSymbol)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingAccessibilityLabel)
            }
        }
        .foregroundStyle(RainflowColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(RainflowColor.brandAccent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(RainflowColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
