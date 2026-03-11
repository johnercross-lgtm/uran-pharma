import SwiftUI

struct ExtempExpertiseNumeroPanel: View {
    let isAutoMode: Bool
    let autoDetectedFormDescription: String
    let expertise: ExtempFormExpertiseSummary?
    let standardSolutionHint: String?
    let buretteHint: String?
    let isLivingDeathActive: Bool
    let shouldShowNumeroField: Bool
    let numeroText: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Експертиза і numero")
                .font(.headline)

            if isAutoMode {
                Text("Автовизначення активне: зараз форма визначена як \(autoDetectedFormDescription). За потреби нижче можна вибрати вручну.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SolarizedTheme.accentColor)
            }

            if let expertise {
                VStack(alignment: .leading, spacing: 8) {
                    Text(expertiseHeadline(for: expertise.title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SolarizedTheme.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Чому саме так")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SolarizedTheme.accentColor.opacity(0.85))

                        Text(expertise.rationale)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(8)
                    .background(SolarizedTheme.backgroundColor.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !expertise.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(expertise.reasons.prefix(2)), id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(SolarizedTheme.backgroundColor.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let standardSolutionHint, !standardSolutionHint.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Готовий розчин")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SolarizedTheme.accentColor)

                    Text(standardSolutionHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(SolarizedTheme.backgroundColor.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let buretteHint, !buretteHint.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Бюреточний шлях")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SolarizedTheme.accentColor)

                    Text(buretteHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(SolarizedTheme.backgroundColor.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if shouldShowNumeroField {
                TextField("Numero (кількість доз)", text: numeroText)
                    .keyboardType(.numberPad)
            }
        }
    }

    private func expertiseHeadline(for title: String) -> String {
        if title.lowercased().contains("мікстура павлова") {
            return "Експертиза: данная пропись — Мікстура Павлова"
        }
        if isLivingDeathActive {
            return "Експертиза: схоже, це \(title)"
        }
        return "Експертиза: рецепт виглядає як \(title)"
    }
}
