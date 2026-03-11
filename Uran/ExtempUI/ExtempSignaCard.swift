import SwiftUI

struct ExtempSignaCard: View {
    let signaText: String
    let precisionHint: String?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Signa")
                    .font(.headline)
                Spacer()
                Button("Открыть") {
                    onOpen()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SolarizedTheme.accentColor)
            }

            Button {
                onOpen()
            } label: {
                Text(signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Нажми, чтобы ввести Signa" : signaText)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(SolarizedTheme.backgroundColor.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if let precisionHint {
                Text(precisionHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }
}
