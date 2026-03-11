import SwiftUI

struct DrugResultRow: View {
    let title: String
    let inn: String
    let formDoseLine: String
    let regLine: String
    let isAnnotated: Bool
    let rxKind: String
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if isAnnotated {
                        Text("исп")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if rxKind == "rx" {
                        Text("Rx")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                    } else if rxKind == "otc" {
                        Text("OTC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else if rxKind == "both" {
                        Text("OTC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                if !inn.isEmpty {
                    Text(inn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !formDoseLine.isEmpty {
                    Text(formDoseLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                        .lineLimit(3)
                }

                if !regLine.isEmpty {
                    Text(regLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(0.65)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
