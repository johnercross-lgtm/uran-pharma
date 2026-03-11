import SwiftUI

struct ExtempCompositionCard: View {
    let ingredients: [IngredientDraft]
    let ingredientSubstanceById: [UUID: ExtempSubstance]
    @Binding var showReorderSheet: Bool
    let amountSummary: (IngredientDraft) -> String
    let ingredientBadges: (IngredientDraft) -> [String]
    let solutionSummary: (IngredientDraft) -> String?
    let warningText: (IngredientDraft) -> String?
    let onOpenIngredient: (UUID) -> Void
    let onRemoveIngredient: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Состав")
                    .font(.headline)
                Spacer()
                Button("Порядок") { showReorderSheet = true }
            }

            if ingredients.isEmpty {
                Text("Добавь ингредиенты через поиск выше")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ingredients) { ingredient in
                    let substance = ingredientSubstanceById[ingredient.id]

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(substance?.nameLatNom ?? ingredient.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                if let gen = substance?.nameLatGen, !gen.isEmpty {
                                    Text(gen)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Text(amountSummary(ingredient))
                                    .font(.system(size: 16, weight: .bold))
                                    .multilineTextAlignment(.trailing)

                                Button("Открыть") {
                                    onOpenIngredient(ingredient.id)
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SolarizedTheme.accentColor)
                            }

                            Button(role: .destructive) {
                                onRemoveIngredient(ingredient.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }

                        classificationBadgeRow(for: ingredient, substance: substance)
                        badgeRow(ingredientBadges(ingredient))

                        if let solution = solutionSummary(ingredient) {
                            Text(solution)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SolarizedTheme.accentColor)
                        }

                        if let warning = warningText(ingredient) {
                            Text(warning)
                                .foregroundStyle(.red)
                                .font(.system(size: 12))
                        }
                    }
                    .padding(12)
                    .uranCard(background: SolarizedTheme.backgroundColor.opacity(0.6), cornerRadius: 16, padding: nil)
                    .onTapGesture {
                        onOpenIngredient(ingredient.id)
                    }
                }
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            NavigationStack {
                List {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { _, ingredient in
                        let title = ingredientSubstanceById[ingredient.id]?.nameLatNom ?? ingredient.displayName
                        Text(title)
                    }
                    .onMove(perform: onMove)
                }
                .navigationTitle("Порядок ингредиентов")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Закрыть") { showReorderSheet = false }
                    }
                }
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func badgeRow(_ labels: [String]) -> some View {
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SolarizedTheme.secondarySurfaceColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func classificationBadgeRow(for ingredient: IngredientDraft, substance: ExtempSubstance?) -> some View {
        let status = UranPharmaClassificationResolver.resolve(ingredient: ingredient, substance: substance)
        HStack(spacing: 6) {
            Text(status.role.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.role.color)
                .foregroundStyle(.white)
                .clipShape(Capsule())

            Text(status.solubility.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.solubility.color.opacity(0.2))
                .foregroundStyle(status.solubility.color)
                .clipShape(Capsule())

            Text(status.risk.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.risk.color)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }
}
