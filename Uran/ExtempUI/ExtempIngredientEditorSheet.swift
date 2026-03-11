import SwiftUI

struct ExtempIngredientEditorSheet: View {
    let ingredient: Binding<IngredientDraft>
    let substance: ExtempSubstance?
    let units: [ExtempUnit]
    let amountText: Binding<String>
    let selectedUnit: Binding<ExtempUnit?>
    let anaFlag: Binding<Bool>
    let qsFlag: Binding<Bool>
    let adFlag: Binding<Bool>
    let showAdToggle: Bool
    let solPercentText: Binding<String>
    let solVolumeText: Binding<String>
    let warningText: String?
    let onDelete: () -> Void
    let onClose: () -> Void
    let onHideKeyboard: () -> Void

    private var isSolution: Bool {
        ingredient.wrappedValue.presentationKind == .solution
    }

    private var russianName: String? {
        guard let substance else { return nil }
        let ru = substance.nameRu.trimmingCharacters(in: .whitespacesAndNewlines)
        let lat = substance.nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ru.isEmpty else { return nil }
        guard ru.caseInsensitiveCompare(lat) != .orderedSame else { return nil }
        return ru
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(substance?.nameLatNom ?? ingredient.wrappedValue.displayName)
                            .font(.system(size: 22, weight: .bold))
                        if let russianName {
                            Text(russianName)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        if let gen = substance?.nameLatGen, !gen.isEmpty {
                            Text(gen)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Основные данные")
                            .font(.system(size: 14, weight: .semibold))

                        TextField("Количество", text: amountText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        Picker("Единица", selection: selectedUnit) {
                            Text("—").tag(ExtempUnit?.none)
                            ForEach(units) { unit in
                                Text(unit.lat.isEmpty ? unit.code : unit.lat).tag(Optional(unit))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Режим количества", selection: ingredient.scope) {
                            Text("Auto").tag(AmountScope.auto)
                            Text("Total").tag(AmountScope.total)
                            Text("Per dose").tag(AmountScope.perDose)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(14)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 18, padding: nil)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Флаги")
                            .font(.system(size: 14, weight: .semibold))

                        Toggle("ana", isOn: anaFlag)
                        Toggle("q.s.", isOn: qsFlag)

                        if showAdToggle {
                            Toggle("ad (довести до)", isOn: adFlag)
                            if ingredient.wrappedValue.isAd {
                                Text("Программа автоматически доведёт состав до конечного объёма.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 18, padding: nil)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Раствор")
                            .font(.system(size: 14, weight: .semibold))

                        TextField("Конц. % или 1:5000", text: solPercentText)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)

                        Text("Можно вводить процент (`0,02`) или соотношение (`1:5000`, `1/5000`).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        TextField("Объём ml", text: solVolumeText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        if isSolution {
                            Text("Эта строка сейчас используется как раствор-источник.")
                                .font(.system(size: 12))
                                .foregroundStyle(SolarizedTheme.accentColor)
                        }
                    }
                    .padding(14)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 18, padding: nil)

                    if let warningText {
                        Text(warningText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    Button("Удалить вещество", role: .destructive) {
                        onDelete()
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SolarizedTheme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Карточка вещества")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        Haptics.tap()
                        onClose()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Скрыть") {
                        onHideKeyboard()
                    }
                }
            }
        }
    }
}
