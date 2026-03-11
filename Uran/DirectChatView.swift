import SwiftUI

struct DirectChatView: View {
    @EnvironmentObject private var session: UserSessionStore

    let otherUid: String
    let otherName: String

    @StateObject private var store = DirectChatStore()

    @State private var messages: [DirectChatMessageDTO] = []
    @State private var newText: String = ""

    private var chatId: String {
        DirectChatStore.chatId(a: session.effectiveUserId, b: otherUid)
    }

    private var trimmedOtherUid: String {
        otherUid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let error = store.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }

                if trimmedOtherUid.isEmpty {
                    Text("Нет UID пользователя")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                ForEach(messages) { m in
                    DirectMessageRow(
                        title: m.fromUid == session.effectiveUserId ? "Вы" : otherName,
                        isMine: m.fromUid == session.effectiveUserId,
                        text: m.text,
                        subtitle: statusText(m)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .task {
                        if m.fromUid != session.effectiveUserId {
                            await store.markDelivered(chatId: chatId, messageId: m.id, myUid: session.effectiveUserId)
                        }
                    }
                    .onAppear {
                        if m.fromUid != session.effectiveUserId {
                            Task {
                                await store.markSeen(chatId: chatId, messageId: m.id, myUid: session.effectiveUserId)
                            }
                        }
                    }
                }

                if messages.isEmpty {
                    Text("Пока нет сообщений")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SolarizedTheme.backgroundColor)

            Divider()

            HStack(spacing: 10) {
                TextField("Сообщение", text: $newText)
                    .textInputAutocapitalization(.sentences)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 12, shadowRadius: 6, shadowY: 3, padding: nil)

                Button("Отправить") {
                    Task {
                        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        await store.sendMessage(chatId: chatId, myUid: session.effectiveUserId, otherUid: trimmedOtherUid, text: t)
                        await MainActor.run { newText = "" }
                    }
                }
                .disabled(trimmedOtherUid.isEmpty || newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(SolarizedTheme.accentColor.opacity(0.18))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(SolarizedTheme.backgroundColor)
        .navigationTitle(otherName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.ensureChat(chatId: chatId, myUid: session.effectiveUserId, otherUid: trimmedOtherUid)
            store.listenMessages(chatId: chatId) { items in
                Task { @MainActor in
                    messages = items
                }
            }
        }
        .onDisappear {
            store.stopListening()
        }
    }

    private func statusText(_ m: DirectChatMessageDTO) -> String {
        guard m.fromUid == session.effectiveUserId else { return "" }
        let delivered = Set(m.deliveredTo).subtracting([session.effectiveUserId]).count
        let seen = Set(m.seenBy).subtracting([session.effectiveUserId]).count
        if seen >= 1 { return "Прочитано" }
        if delivered >= 1 { return "Доставлено" }
        return "Отправлено"
    }
}

private struct DirectMessageRow: View {
    let title: String
    let isMine: Bool
    let text: String
    let subtitle: String

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(text)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isMine ? SolarizedTheme.accentColor.opacity(0.18) : SolarizedTheme.secondarySurfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    NavigationStack {
        DirectChatView(otherUid: "u2", otherName: "Друг")
            .environmentObject(UserSessionStore())
    }
}
