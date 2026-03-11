import SwiftUI
import UIKit

enum SolarizedTheme {
    enum Mode: String {
        case light
        case dark
    }

    enum Accent: String, CaseIterable {
        case red
        case orange
        case yellow
        case green
        case cyan
        case blue
        case violet
        case magenta
    }

    static let modeDefaultsKey = "themeMode"
    static let accentDefaultsKey = "accentColor"

    // NOTE:
    // This app has a lot of UI code written against `SolarizedTheme.*`.
    // To keep refactors cheap, we map those tokens to *system* dynamic colors.
    // Result: iOS-native look, automatic Light/Dark, Dynamic Type friendly.
    static let base03 = UIColor.label
    static let base02 = UIColor.secondaryLabel
    static let base01 = UIColor.tertiaryLabel
    static let base00 = UIColor.label
    static let base0 = UIColor.label
    static let base1 = UIColor.secondaryLabel
    static let base2 = UIColor.secondarySystemBackground
    static let base3 = UIColor.systemBackground

    static let darkBackground = UIColor.systemBackground
    static let darkSurface = UIColor.secondarySystemBackground
    static let darkSecondarySurface = UIColor.tertiarySystemBackground
    static let darkBorder = UIColor.separator

    static let yellow = UIColor.systemYellow
    static let orange = UIColor.systemOrange
    static let red = UIColor.systemRed
    static let magenta = UIColor.systemPink
    static let violet = UIColor.systemPurple
    static let blue = UIColor.systemBlue
    static let cyan = UIColor.systemTeal
    static let green = UIColor.systemGreen

    static var currentMode: Mode {
        let raw = UserDefaults.standard.string(forKey: modeDefaultsKey) ?? Mode.light.rawValue
        return Mode(rawValue: raw) ?? .light
    }

    static func setMode(_ mode: Mode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
    }

    static var currentAccent: Accent {
        let raw = UserDefaults.standard.string(forKey: accentDefaultsKey) ?? Accent.orange.rawValue
        return Accent(rawValue: raw) ?? .orange
    }

    static func setAccent(_ accent: Accent) {
        UserDefaults.standard.set(accent.rawValue, forKey: accentDefaultsKey)
    }

    static func color(for accent: Accent) -> UIColor {
        switch accent {
        case .red: return red
        case .orange: return orange
        case .yellow: return yellow
        case .green: return green
        case .cyan: return cyan
        case .blue: return blue
        case .violet: return violet
        case .magenta: return magenta
        }
    }

    static var accentUIColor: UIColor { UIColor.systemBlue }

    static var accentColor: Color { Color(uiColor: accentUIColor) }

    static var backgroundUIColor: UIColor { .systemBackground }

    static var surfaceUIColor: UIColor { .secondarySystemBackground }

    static var secondarySurfaceUIColor: UIColor { .tertiarySystemBackground }

    static var borderUIColor: UIColor { .separator }

    static var primaryTextUIColor: UIColor { .label }

    static var secondaryTextUIColor: UIColor { .secondaryLabel }

    static var backgroundColor: Color { Color(uiColor: backgroundUIColor) }
    static var surfaceColor: Color { Color(uiColor: surfaceUIColor) }
    static var secondarySurfaceColor: Color { Color(uiColor: secondarySurfaceUIColor) }
    static var borderColor: Color { Color(uiColor: borderUIColor) }

    static var cardCornerRadius: CGFloat { 14 }
    static var cardShadowColor: Color { Color.black.opacity(0.0) }
    static var cardShadowRadius: CGFloat { 0 }
    static var cardShadowYOffset: CGFloat { 0 }

    /// Kept for backward compatibility. We intentionally do not override UIKit appearances anymore.
    static func apply(mode: Mode = currentMode) {
        // no-op (system look)
        _ = mode
    }
}

extension View {
    func uranCard(
        background: Color = SolarizedTheme.secondarySurfaceColor,
        border: Color = SolarizedTheme.borderColor,
        cornerRadius: CGFloat = SolarizedTheme.cardCornerRadius,
        shadowColor: Color = SolarizedTheme.cardShadowColor,
        shadowRadius: CGFloat = SolarizedTheme.cardShadowRadius,
        shadowY: CGFloat = SolarizedTheme.cardShadowYOffset,
        padding: CGFloat? = nil
    ) -> some View {
        self
            .padding(padding ?? 0)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

private extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
