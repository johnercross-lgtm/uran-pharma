import SwiftUI
import UIKit

struct ExtempOutputsCard: View {
    let topBlockingIssueText: String?
    let shadowReport: SolutionEngineShadowReport?
    @Binding var isResultExpanded: Bool
    @Binding var isPpkExpanded: Bool
    let rxText: String
    let ppkText: String
    let hasRxOutputText: Bool
    let hasPpkOutputText: Bool
    let combinedOutputText: String
    let hasCombinedOutputText: Bool
    let onOpenResult: () -> Void
    let onOpenBurette: () -> Void
    let onOpenEthanolCalculator: () -> Void
    let onOpenPpk: () -> Void
    let onCopyCombined: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let topBlockingIssueText {
                Text("⛔ \(topBlockingIssueText)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let shadowReport {
                VStack(alignment: .leading, spacing: 4) {
                    let engineTitle = shadowReport.v1SelectedAsPrimary
                        ? "Новый движок жидких форм (v1)"
                        : "Классический движок"
                    Text("Активный движок: \(engineTitle)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(shadowReport.v1SelectedAsPrimary ? .green : .secondary)
                    Text(shadowReport.preferV1Enabled
                         ? "Режим: для жидких форм приоритет у нового движка."
                         : "Режим: работает классический движок.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if shadowReport.compared {
                        Text("Сверка движков: \(shadowReport.hasMismatch ? "есть расхождения" : "расхождений нет"), уровень: \(localizedMismatchSeverity(shadowReport.mismatchSeverity))")
                            .font(.system(size: 11))
                            .foregroundStyle(shadowReport.mismatchSeverity == .critical ? .red : .secondary)
                        if shadowReport.hasMismatch {
                            Text("Причины: \(shadowReport.mismatchReasons.joined(separator: ", "))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    } else {
                        Text("Сверка движков: недоступна")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let reasoning = shadowReport.reasoningShadow {
                        Text("Сверка логики принятия решений: \(reasoning.hasMismatch ? "есть расхождения" : "расхождений нет")")
                            .font(.system(size: 11))
                            .foregroundStyle(reasoning.hasMismatch ? .orange : .secondary)
                        if reasoning.hasMismatch {
                            Text("Причины по логике: \(reasoning.mismatchReasons.joined(separator: ", "))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            DisclosureGroup("Результат", isExpanded: $isResultExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    RxPrettyText(text: rxText)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button("Открыть") {
                            Haptics.tap()
                            onOpenResult()
                        }
                        .disabled(!hasRxOutputText)
                    }

                    HStack(spacing: 12) {
                        Button("Бюретка") {
                            Haptics.tap()
                            onOpenBurette()
                        }
                        .foregroundStyle(SolarizedTheme.accentColor)

                        Button("Спирт") {
                            Haptics.tap()
                            onOpenEthanolCalculator()
                        }
                        .foregroundStyle(SolarizedTheme.accentColor)
                    }
                }
                .padding(.top, 8)
            }

            if !ppkText.isEmpty {
                DisclosureGroup("ППК", isExpanded: $isPpkExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        PpkPrettyText(text: ppkText)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Button("Открыть") {
                                Haptics.tap()
                                onOpenPpk()
                            }
                            .disabled(!hasPpkOutputText)
                            .foregroundStyle(SolarizedTheme.accentColor)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            HStack(spacing: 12) {
                Button("Копировать Rp + ППК") {
                    Haptics.tap()
                    onCopyCombined()
                }
                .foregroundStyle(SolarizedTheme.accentColor)
                .disabled(!hasCombinedOutputText)

                ShareLink(item: combinedOutputText) {
                    Text("Поделиться")
                }
                .foregroundStyle(SolarizedTheme.accentColor)
                .disabled(!hasCombinedOutputText)
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }

    private func localizedMismatchSeverity(_ value: SolutionShadowMismatchSeverity) -> String {
        switch value {
        case .none:
            return "нет"
        case .nonCritical:
            return "некритично"
        case .critical:
            return "критично"
        }
    }
}

struct RxPrettyText: View {
    let text: String

    var body: some View {
        Text(attributedText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        let lines = text.components(separatedBy: .newlines)
        var result = AttributedString()

        for (index, rawLine) in lines.enumerated() {
            var line = AttributedString(rawLine)
            line.font = .system(size: 16, weight: .regular, design: .monospaced)
            line.foregroundColor = .primary
            SubstanceTokenHighlighter.apply(to: &line, source: rawLine)
            result.append(line)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }
}
