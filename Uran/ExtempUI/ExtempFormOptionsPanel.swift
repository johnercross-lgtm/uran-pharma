import SwiftUI

struct ExtempFormOptionsPanel<StandardSolutionsContent: View>: View {
    @Binding var isExpanded: Bool
    let formMode: Binding<FormMode>
    let availableFormModes: [FormMode]
    let isAutoMode: Bool
    let effectiveFormMode: FormMode
    let liquidTechnologyMode: Binding<LiquidTechnologyMode>
    let ophthalmicDrops: Binding<Bool>
    let useBuretteSystem: Binding<Bool>
    let useVmsColloids: Binding<Bool>
    let useStandardSolutions: Binding<Bool>
    let isStandardSolutionsEnabled: Bool
    let showPpkSteps: Binding<Bool>
    let showExtendedTech: Binding<Bool>
    let powderMassMode: Binding<PowderMassMode>
    let metrologyScale: Binding<MetrologicalScaleSelection>
    let metrologyDropperMode: Binding<MetrologicalDropperMode>
    let metrologyDropperDropsPerMlWaterText: Binding<String>
    let metrologyCorrectionVolumeMlText: Binding<String>
    let metrologyCorrectionActualPercentText: Binding<String>
    let metrologyCorrectionTargetPercentText: Binding<String>
    let metrologyCorrectionStockPercentText: Binding<String>
    let targetText: Binding<String>
    let targetUnitId: Binding<Int?>
    let units: [ExtempUnit]
    let hasAdIngredient: Bool
    let selectedStandardSolutionName: String?
    let onOpenStandardSolutionsCatalog: () -> Void
    let onOpenSpecialCasesCatalog: () -> Void
    @ViewBuilder let standardSolutionsPanel: () -> StandardSolutionsContent

    var body: some View {
        DisclosureGroup("Форма", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Можна залишити автовизначення форми або в будь-який момент вибрати тип вручну.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                Picker("Тип", selection: formMode) {
                    ForEach(availableFormModes, id: \.id) { mode in
                        if mode == .auto {
                            Text("Авто (рекомендовано)").tag(mode)
                        } else {
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                .pickerStyle(.menu)

                if isAutoMode {
                    Text("Автоматично застосовано: \(effectiveFormMode.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if effectiveFormMode == .solutions {
                    Picker("Гілка рідкої технології", selection: liquidTechnologyMode) {
                        ForEach(LiquidTechnologyMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if effectiveFormMode == .drops {
                    Toggle("Очні краплі (стерильно)", isOn: ophthalmicDrops)
                }

                if effectiveFormMode == .solutions || effectiveFormMode == .drops {
                    Text("Додаткові блоки вмикаються тільки вручну:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Toggle("Бюретка (концентровані розчини)", isOn: useBuretteSystem)
                    Toggle("ВМС / колоїди", isOn: useVmsColloids)
                    Toggle("Стандартні розчини (ГФ)", isOn: useStandardSolutions)
                }

                if isStandardSolutionsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Haptics.tap()
                            onOpenStandardSolutionsCatalog()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet.rectangle")
                                    .foregroundStyle(SolarizedTheme.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Каталог готових розчинів")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(selectedStandardSolutionName ?? "Вибери фармакопейний розчин, введи % і об’єм, потім застосуй у рецепт.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(SolarizedTheme.backgroundColor.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Text("Каталог містить захардкожені стандартні фармакопейні розчини. Усередині можна швидко вибрати розчин і переглянути ППК-прев’ю.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    standardSolutionsPanel()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Haptics.tap()
                        onOpenSpecialCasesCatalog()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "staroflife")
                                .foregroundStyle(SolarizedTheme.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Особливі випадки")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Окремий каталог для Люголя та інших нетипових технологічних шаблонів.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(SolarizedTheme.backgroundColor.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Toggle("Показувати розрахунки", isOn: showPpkSteps)
                Toggle("Деталі технології", isOn: showExtendedTech)

                if effectiveFormMode == .powders {
                    Picker("Маса для порошків", selection: powderMassMode) {
                        ForEach(PowderMassMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Group {
                    Text("Метрологія")
                        .font(.system(size: 12, weight: .semibold))

                    Picker("Тип ваг", selection: metrologyScale) {
                        ForEach(MetrologicalScaleSelection.allCases, id: \.self) { selection in
                            Text(selection.title).tag(selection)
                        }
                    }
                    .pickerStyle(.menu)

                    if effectiveFormMode == .drops || effectiveFormMode == .solutions {
                        Picker("Краплемір", selection: metrologyDropperMode) {
                            ForEach(MetrologicalDropperMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)

                        if metrologyDropperMode.wrappedValue == .nonStandard {
                            TextField("n: кількість крапель у 1 ml води", text: metrologyDropperDropsPerMlWaterText)
                                .keyboardType(.decimalPad)
                        }

                        Text("Корекція концентрації (якщо Cfact відрізняється від Cneeded):")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("V наявного розчину, ml", text: metrologyCorrectionVolumeMlText)
                            .keyboardType(.decimalPad)
                        TextField("Cfact, %", text: metrologyCorrectionActualPercentText)
                            .keyboardType(.decimalPad)
                        TextField("Cneeded, %", text: metrologyCorrectionTargetPercentText)
                            .keyboardType(.decimalPad)
                        TextField("Cstock, % (для укріплення, опц.)", text: metrologyCorrectionStockPercentText)
                            .keyboardType(.decimalPad)
                    }
                }

                TextField("Загальна маса/обʼєм (для ad/q.s.)", text: targetText)
                    .keyboardType(.decimalPad)

                Picker("Одиниця (для ad/q.s.)", selection: targetUnitId) {
                    Text("—").tag(Int?.none)
                    ForEach(units) { unit in
                        Text(unit.lat.isEmpty ? unit.code : unit.lat).tag(Optional(unit.id))
                    }
                }
                .pickerStyle(.menu)

                if hasAdIngredient {
                    Text("Формула для ad: V_water = V_target - ΣV_other_liquids - ΣV_displacement (якщо застосовується КУО).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }
}
