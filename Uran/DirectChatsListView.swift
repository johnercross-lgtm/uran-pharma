import SwiftUI

struct DirectChatsListView: View {
    @EnvironmentObject private var session: UserSessionStore

    @StateObject private var store = HomeStore()
    @StateObject private var forumStore = WikiForumStore()

    @State private var isFriendsPresented: Bool = false

    var body: some View {
        List {
            if let error = store.errorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(store.chats) { chat in
                    NavigationLink {
                        DirectChatView(otherUid: chat.otherUid, otherName: chat.otherName)
                            .onAppear { HomeStore.markChatSeen(chatId: chat.id) }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(chat.isUnread ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "message.fill")
                                    .foregroundStyle(chat.isUnread ? Color.accentColor : .secondary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(displayName(for: chat))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    if chat.isUnread {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 8, height: 8)
                                    }
                                }

                                Text(displaySubtitle(for: chat))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if store.chats.isEmpty {
                    ContentUnavailableView(
                        "Нет диалогов",
                        systemImage: "message",
                        description: Text("Открой друзей и начни переписку")
                    )
                }
            }
        }
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFriendsPresented = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isFriendsPresented) {
            NavigationStack {
                FriendsView(store: FriendsStore())
            }
        }
        .task(id: session.userId) {
            store.listen(myUid: session.effectiveUserId, forumStore: forumStore, chatLimit: 50)
        }
        .onDisappear {
            store.stop()
            forumStore.stopListeningThreads()
        }
    }

    private func displayName(for chat: HomeChatSummary) -> String {
        let name = chat.otherName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Диалог" : name
    }

    private func displaySubtitle(for chat: HomeChatSummary) -> String {
        let text = chat.lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Открыть чат" : text
    }
}

#Preview {
    NavigationStack {
        DirectChatsListView()
            .environmentObject(UserSessionStore())
    }
}
