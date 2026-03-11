import SwiftUI

struct WikiForumThreadDetailView: View {
    @EnvironmentObject private var session: UserSessionStore
    @StateObject private var store = WikiForumStore()

    let threadId: String
    let threadTitle: String

    @State private var posts: [WikiForumPostDTO] = []
    @State private var newText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(threadTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SolarizedTheme.accentColor)

                        Text("Ответов: \(posts.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                if let error = store.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }

                Section("Ответы") {
                    ForEach(posts) { p in
                        ForumPostCard(
                            author: p.fromName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(p.fromUid.prefix(8)) : p.fromName,
                            date: p.createdAt,
                            text: p.text
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    if posts.isEmpty {
                        Text("Пока нет ответов")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SolarizedTheme.backgroundColor)

            Divider()

            VStack(spacing: 10) {
                TextField("Написать ответ", text: $newText)
                    .textInputAutocapitalization(.sentences)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 12, shadowRadius: 6, shadowY: 3, padding: nil)

                HStack {
                    Spacer()
                    Button("Отправить") {
                        Task {
                            let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            await store.addPost(
                                threadId: threadId,
                                text: t,
                                myUid: session.effectiveUserId,
                                myName: session.displayName
                            )
                            await MainActor.run { newText = "" }
                        }
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .navigationTitle("Тема")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.listenPosts(threadId: threadId) { items in
                Task { @MainActor in
                    posts = items
                }
            }
        }
        .onDisappear {
            store.stopListeningPosts()
        }
    }
}

private struct ForumPostCard: View {
    let author: String
    let date: Date?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let date {
                    Text(date, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 14, shadowRadius: 8, shadowY: 4, padding: nil)
    }
}

#Preview {
    NavigationStack {
        WikiForumThreadDetailView(threadId: "t1", threadTitle: "Тема")
            .environmentObject(UserSessionStore())
    }
}
