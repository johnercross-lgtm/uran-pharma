import SwiftUI
import UIKit

struct ExtempEthanolCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    let showsCloseButton: Bool

    @State private var mode: EthanolCalculatorMode = .fertman
    @State private var sourceVolumeText: String = "100"
    @State private var sourcePercentText: String = "96"
    @State private var targetPercentText: String = "70"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                inputCard
                resultCard
                rulesCard
            }
            .padding(12)
        }
        .navigationTitle("Калькулятор спирта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Режим")
                .font(.headline)

            Picker("Режим", selection: $mode) {
                ForEach(EthanolCalculatorMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(mode.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Group {
                labeledField(title: "Исходный объем спирта, ml", text: $sourceVolumeText)
                labeledField(title: "Исходная крепость, %", text: $sourcePercentText)
                labeledField(title: "Целевая крепость, %", text: $targetPercentText)
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
    }

    @ViewBuilder
    private var resultCard: some View {
        switch calculationState {
        case .idle:
            EmptyView()
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Расчет")
                    .font(.headline)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }
            .padding(12)
            .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        case .success(let result):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Добавить воды")
                            .font(.headline)
                        Text("\(ExtempViewFormatter.formatAmount(result.waterToAddMl)) ml")
                            .font(.system(size: 28, weight: .bold))
                    }
                    Spacer()
                    Button("Копировать") {
                        UIPasteboard.general.string = copyText(for: result)
                        Haptics.success()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SolarizedTheme.accentColor)
                }

                metricRow(title: "Исходный спирт", value: "\(ExtempViewFormatter.formatAmount(result.sourceVolumeMl)) ml \(ExtempViewFormatter.formatAmount(result.sourcePercent))%")
                metricRow(title: "Смесь до контракции", value: "\(ExtempViewFormatter.formatAmount(result.totalBeforeContractionMl)) ml")
                metricRow(title: result.usedTabularProMode ? "Ожидаемый итог после смешивания" : "Теоретический итог", value: "\(ExtempViewFormatter.formatAmount(result.expectedFinalVolumeMl)) ml")

                if result.usedTabularProMode {
                    metricRow(title: "Оценка контракции", value: "\(ExtempViewFormatter.formatAmount(result.contractionMl)) ml")
                }

                if result.mode == .fertman {
                    Text(result.usedFallbackFormula ? "Pro-режим вышел за пределы таблицы Фертмана и временно перешел на обычную формулу." : "Использован табличный расчет Фертмана при 20°C.")
                        .font(.system(size: 12))
                        .foregroundStyle(result.usedFallbackFormula ? .orange : .secondary)
                }

                if let interpolationText = interpolationText(for: result), !interpolationText.isEmpty {
                    Text(interpolationText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        }
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Справка")
                .font(.headline)

            ruleLine("Лей спирт в воду, а не наоборот.")
            ruleLine("Ориентируйся на температуру 20°C: при холодном или горячем спирте плотность и ареометрия смещаются.")
            ruleLine("Используй мягкую очищенную или дистиллированную воду, чтобы избежать помутнения и осадка.")
            ruleLine("В Pro-режиме таблица покрывает примерно 95→40% до 30% и интерполирует между соседними значениями.")
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
    }

    private func labeledField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
    }

    private func ruleLine(_ text: String) -> some View {
        Text("• \(text)")
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calculationState: CalculationState {
        guard let sourceVolume = parseDouble(sourceVolumeText),
              let sourcePercent = parseDouble(sourcePercentText),
              let targetPercent = parseDouble(targetPercentText) else {
            if sourceVolumeText.isEmpty && sourcePercentText.isEmpty && targetPercentText.isEmpty {
                return .idle
            }
            return .error("Заполни объем и обе крепости.")
        }

        do {
            let result = try EthanolQuickCalculator.calculate(
                sourceVolumeMl: sourceVolume,
                sourcePercent: sourcePercent,
                targetPercent: targetPercent,
                mode: mode
            )
            return .success(result)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func interpolationText(for result: EthanolCalculatorResult) -> String? {
        var parts: [String] = []
        if let sourceRange = result.sourceInterpolationRange {
            parts.append("По исходной крепости интерполяция между \(sourceRange.lowerBound)% и \(sourceRange.upperBound)%.")
        }
        if let targetRange = result.targetInterpolationRange {
            parts.append("По целевой крепости интерполяция между \(targetRange.lowerBound)% и \(targetRange.upperBound)%.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func copyText(for result: EthanolCalculatorResult) -> String {
        var lines: [String] = [
            "Разведение спирта",
            "Исходный спирт: \(ExtempViewFormatter.formatAmount(result.sourceVolumeMl)) ml \(ExtempViewFormatter.formatAmount(result.sourcePercent))%",
            "Целевая крепость: \(ExtempViewFormatter.formatAmount(result.targetPercent))%",
            "Добавить воды: \(ExtempViewFormatter.formatAmount(result.waterToAddMl)) ml",
            "Смесь до контракции: \(ExtempViewFormatter.formatAmount(result.totalBeforeContractionMl)) ml",
            "Ожидаемый итог: \(ExtempViewFormatter.formatAmount(result.expectedFinalVolumeMl)) ml"
        ]
        if result.usedTabularProMode {
            lines.append("Контракция: \(ExtempViewFormatter.formatAmount(result.contractionMl)) ml")
        }
        if result.mode == .fertman {
            lines.append(result.usedFallbackFormula ? "Режим: Pro, fallback на формулу" : "Режим: Pro (Фертман)")
        } else {
            lines.append("Режим: Формула")
        }
        return lines.joined(separator: "\n")
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

private enum CalculationState {
    case idle
    case success(EthanolCalculatorResult)
    case error(String)
}

struct ExtempEthanolCalculatorSheet: View {
    var body: some View {
        NavigationStack {
            ExtempEthanolCalculatorView(showsCloseButton: true)
        }
    }
}
