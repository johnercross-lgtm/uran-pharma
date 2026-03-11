import SwiftUI

struct ExtempBuretteReferenceView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case prescription
        case manufacturing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .prescription:
                return "Для рецепта"
            case .manufacturing:
                return "Для концентрата"
            }
        }
    }

    let showsCloseButton: Bool

    @State private var mode: Mode = .prescription
    @State private var selectedConcentrateId: String = BuretteSystem.concentrates.first?.id ?? ""
    @State private var soluteMassText: String = ""
    @State private var totalMixtureVolumeText: String = ""
    @State private var otherLiquidsText: String = ""

    @State private var selectedRecipeId: String = BuretteSystem.manufacturingRecipes.first?.id ?? ""
    @State private var batchVolumeText: String = "500"

    private var selectedConcentrate: BuretteSystem.Concentrate? {
        BuretteSystem.concentrates.first(where: { $0.id == selectedConcentrateId }) ?? BuretteSystem.concentrates.first
    }

    private var selectedRecipe: BuretteSystem.ManufacturingRecipe? {
        BuretteSystem.manufacturingRecipes.first(where: { $0.id == selectedRecipeId }) ?? BuretteSystem.manufacturingRecipes.first
    }

    private var soluteMass: Double? {
        parseNumber(soluteMassText)
    }

    private var totalMixtureVolume: Double? {
        parseNumber(totalMixtureVolumeText)
    }

    private var otherLiquidsVolume: Double {
        max(0, parseNumber(otherLiquidsText) ?? 0)
    }

    private var batchVolume: Double? {
        parseNumber(batchVolumeText)
    }

    private var concentrateVolume: Double? {
        guard let concentrate = selectedConcentrate, let soluteMass, soluteMass > 0 else { return nil }
        return soluteMass * concentrate.mlPerG
    }

    private var purifiedWaterForMixture: Double? {
        guard let totalMixtureVolume, totalMixtureVolume > 0, let concentrateVolume else { return nil }
        return totalMixtureVolume - concentrateVolume - otherLiquidsVolume
    }

    private var manufacturingMass: Double? {
        guard let recipe = selectedRecipe, let batchVolume, batchVolume > 0 else { return nil }
        return batchVolume * recipe.concentrationPercent / 100.0
    }

    private var manufacturingWater: Double? {
        guard let recipe = selectedRecipe, let batchVolume, batchVolume > 0, let manufacturingMass else { return nil }
        return batchVolume - manufacturingMass * recipe.kuoMlPerG
    }

    var body: some View {
        List {
            Section {
                Picker("Режим", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(mode == .prescription
                     ? "Выбираешь готовый концентрат, вводишь массу вещества по рецепту и при необходимости общий объём микстуры."
                     : "Выбираешь раствор для бюретки и сразу получаешь массу вещества и объём воды по КУО.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if mode == .prescription {
                prescriptionCalculatorSection
            } else {
                manufacturingCalculatorSection
            }

            Section {
                ForEach(BuretteSystem.dosingRules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(rule.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Правила работы")
            }

            Section {
                ForEach(BuretteSystem.stockQualityControlLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                }
                Divider()
                ForEach(BuretteSystem.labelingLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                }
            } header: {
                Text("Контроль и маркировка")
            }
        }
        .navigationTitle("Бюретка")
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

    private var prescriptionCalculatorSection: some View {
        Section {
            Picker("Концентрат", selection: $selectedConcentrateId) {
                ForEach(BuretteSystem.concentrates) { concentrate in
                    Text("\(concentrate.titleRu) (\(concentrate.ratioTitle))")
                        .tag(concentrate.id)
                }
            }
            .pickerStyle(.menu)

            TextField("Масса вещества по рецепту, g", text: $soluteMassText)
                .keyboardType(.decimalPad)

            TextField("Общий объём микстуры, ml", text: $totalMixtureVolumeText)
                .keyboardType(.decimalPad)

            TextField("Другие жидкости, ml", text: $otherLiquidsText)
                .keyboardType(.decimalPad)

            if let concentrate = selectedConcentrate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Концентрат: \(concentrate.concentrationTitle), \(concentrate.ratioTitle)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(concentrate.meniscusEdge.guidance)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let soluteMass, soluteMass > 0, let concentrateVolume {
                        Text("V_conc = \(fmt(soluteMass)) × \(fmt(concentrate.mlPerG)) = \(fmt(concentrateVolume)) ml")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("Введи массу вещества, чтобы посчитать объём концентрата.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if let totalMixtureVolume, totalMixtureVolume > 0, let purifiedWaterForMixture {
                        if purifiedWaterForMixture >= 0 {
                            Text("Aqua purificata = \(fmt(totalMixtureVolume)) - \(fmt(concentrateVolume ?? 0)) - \(fmt(otherLiquidsVolume)) = \(fmt(purifiedWaterForMixture)) ml")
                                .font(.system(size: 13, weight: .semibold))
                        } else {
                            Text("Вода выходит отрицательной: уменьши объём концентрата/других жидкостей или увеличь общий объём.")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("Если нужен расчёт воды для микстуры, укажи общий объём и объём остальных жидкостей.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text("КУО сухих веществ тут не учитывается, потому что вещество вводится уже как готовый концентрат.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Калькулятор для рецепта")
        } footer: {
            Text("Пример: для 2,0 g Natrii bromidum 20% программа даст 10 ml концентрата.")
        }
    }

    private var manufacturingCalculatorSection: some View {
        Section {
            Picker("Раствор", selection: $selectedRecipeId) {
                ForEach(BuretteSystem.manufacturingRecipes) { recipe in
                    Text("\(recipe.title) (\(recipe.ratioTitle))")
                        .tag(recipe.id)
                }
            }
            .pickerStyle(.menu)

            TextField("Объём партии, ml", text: $batchVolumeText)
                .keyboardType(.decimalPad)

            if let recipe = selectedRecipe {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Концентрация: \(BuretteSystem.percentText(recipe.concentrationPercent)), КУО \(fmt(recipe.kuoMlPerG))")
                        .font(.system(size: 13, weight: .semibold))

                    if let batchVolume, batchVolume > 0,
                       let manufacturingMass,
                       let manufacturingWater
                    {
                        Text("m = \(fmt(batchVolume)) × \(fmt(recipe.concentrationPercent / 100.0)) = \(fmt(manufacturingMass)) g")
                            .font(.system(size: 13, weight: .semibold))
                        Text("V_H2O = \(fmt(batchVolume)) - (\(fmt(manufacturingMass)) × \(fmt(recipe.kuoMlPerG))) = \(fmt(manufacturingWater)) ml")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("Введи объём партии, чтобы посчитать массу вещества и воду.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(recipe.notes, id: \.self) { line in
                        Text("• \(line)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text(recipe.qualityControlNote)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Калькулятор концентрата")
        } footer: {
            Text("Если работаешь через мерную колбу, сначала растворяешь вещество в части воды, затем доводишь объём до метки.")
        }
    }

    private func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func fmt(_ value: Double) -> String {
        BuretteSystem.format(value)
    }
}

struct ExtempBuretteSheet: View {
    var body: some View {
        NavigationStack {
            ExtempBuretteReferenceView(showsCloseButton: true)
        }
    }
}
