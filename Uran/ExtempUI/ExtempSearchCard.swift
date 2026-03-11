import SwiftUI

struct ExtempSearchCard: View {
    @Binding var query: String

    let results: [ExtempSubstance]
    let isLoading: Bool
    let incompatibilityMessage: String?
    let incompatibilityIsBlocking: Bool
    let canClearComposition: Bool
    let onQueryChanged: (String) -> Void
    let onClearQuery: () -> Void
    let onClearComposition: () -> Void
    let onSelectSubstance: (ExtempSubstance) -> Void
    let debugInfo: ((ExtempSubstance) -> String?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Название / лат. / inn_key", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onChange(of: query) { _, newValue in
                    onQueryChanged(newValue)
                }

            HStack(spacing: 12) {
                Button("Очистить") {
                    Haptics.tap()
                    onClearQuery()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button("Очистить состав") {
                    onClearComposition()
                }
                .foregroundStyle(.red)
                .disabled(!canClearComposition)
            }
            .font(.system(size: 13, weight: .semibold))

            if let incompatibilityMessage, !incompatibilityMessage.isEmpty {
                Text(incompatibilityMessage)
                    .foregroundStyle(incompatibilityIsBlocking ? Color.red : Color.orange)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results.prefix(10)) { substance in
                        Button {
                            Haptics.tap()
                            onSelectSubstance(substance)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(substance.nameRu.isEmpty ? substance.nameLatNom : substance.nameRu)
                                    .font(.system(size: 14, weight: .semibold))
                                Text("\(substance.nameLatNom) → \(substance.nameLatGen)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
#if DEBUG
                                if let debugInfo, let caption = debugInfo(substance), !caption.isEmpty {
                                    Text(caption)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
#endif
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .uranCard(background: SolarizedTheme.backgroundColor.opacity(0.6), cornerRadius: 14, padding: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }
}
