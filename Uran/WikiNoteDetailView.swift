import SwiftUI

struct WikiNoteDetailView: View {
    let item: NoteFeedItem
    let authorName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let title = item.note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(title.isEmpty ? "Без названия" : title)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let d = Date(timeIntervalSince1970: Double(item.note.updatedAt))
                    Text(d, format: .dateTime.day().month().year().hour().minute())
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)

                    let uid = (item.note.updatedByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let storedName = (item.note.updatedByName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedName = storedName.isEmpty ? (authorName ?? "") : storedName
                    if !resolvedName.isEmpty {
                        Text("by \(resolvedName)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if !uid.isEmpty {
                        Text("by \(String(uid.prefix(8)))")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    let folder = item.folderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !folder.isEmpty {
                        Text(folder)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Divider()

                Text(item.note.content)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(16)
        }
        .navigationTitle("Конспект")
        .navigationBarTitleDisplayMode(.inline)
    }
}
