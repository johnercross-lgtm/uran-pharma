import SwiftUI

public struct RootView: View {
    public init() {}

    @AppStorage(SolarizedTheme.modeDefaultsKey) private var themeModeRaw = SolarizedTheme.currentMode.rawValue

    private var preferredThemeScheme: ColorScheme? {
        switch SolarizedTheme.Mode(rawValue: themeModeRaw) ?? .light {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    public var body: some View {
        ContentView()
            .preferredColorScheme(preferredThemeScheme)
    }
}

#Preview {
    RootView()
}
