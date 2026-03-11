import SwiftUI
import UIKit

struct ExtempStandardSolutionsPanel: View {
    @Binding var sourceKey: SolutionKey?
    @Binding var stockText: String
    @Binding var waterText: String
    @Binding var noteText: String

    let manualTotalMl: Double?
    private let solutions = StandardSolutionsRepository.shared.solutions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ручний режим для стандартного розчину")
                    .font(.system(size: 12, weight: .semibold))

                Picker("Вихідний стандартний розчин", selection: $sourceKey) {
                    Text("Автовизначення").tag(SolutionKey?.none)
                    ForEach(solutions) { solution in
                        Text(solution.chemicalName).tag(Optional(solution.id))
                    }
                }
                .pickerStyle(.menu)

                TextField("Стандартний розчин, ml", text: $stockText)
                    .keyboardType(.decimalPad)

                TextField("Aqua purificata, ml", text: $waterText)
                    .keyboardType(.decimalPad)

                TextField("Примітка / ручний розрахунок для ППК", text: $noteText, axis: .vertical)
                    .lineLimit(2...4)

                if let manualTotalMl, manualTotalMl > 0 {
                    Text("Ручна суміш: \(ExtempViewFormatter.formatPercentValue(manualTotalMl)) ml")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(SolarizedTheme.backgroundColor.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
