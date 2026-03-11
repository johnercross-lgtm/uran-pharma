import SwiftUI

struct ExtempTechPlanCard: View {
    let steps: [TechStep]
    let showExtendedTech: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Технологія")
                .font(.headline)

            if steps.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(idx + 1). \(step.isCritical ? "⚠ " : "")\(step.title)")
                                .font(.system(size: 14, weight: step.isCritical ? .semibold : .regular))

                            if showExtendedTech,
                               let notes = step.notes,
                               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(notes)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }
}
