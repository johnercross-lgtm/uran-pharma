import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct HomeChatSummary: Identifiable, Hashable {
    var id: String
    var otherUid: String
    var otherName: String
    var lastText: String
    var updatedAt: Date?
    var isUnread: Bool
}

struct HomeNoteSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var updatedAt: Date?
    var updatedByName: String
}

@MainActor
final class HomeStore: ObservableObject {
    @Published var chats: [HomeChatSummary] = []
    @Published var notes: [HomeNoteSummary] = []
    @Published var threads: [WikiForumThreadDTO] = []

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var nameCache: [String: String] = [:]

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var chatsListener: ListenerRegistration?
    private var notesListener: ListenerRegistration?
    #endif

    deinit {
        #if canImport(FirebaseFirestore)
        chatsListener?.remove()
        chatsListener = nil
        notesListener?.remove()
        notesListener = nil
        #endif
    }

    func stop() {
        #if canImport(FirebaseFirestore)
        chatsListener?.remove()
        chatsListener = nil
        notesListener?.remove()
        notesListener = nil
        #endif
    }

    func listen(myUid: String, forumStore: WikiForumStore, chatLimit: Int = 10, noteLimit: Int = 8, threadLimit: Int = 8) {
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            chats = []
            notes = []
            threads = []
            return
        }

        errorMessage = nil
        isLoading = true

        forumStore.listenThreads(limit: threadLimit)

        #if canImport(FirebaseFirestore)
        chatsListener?.remove()
        chatsListener = db.collection("directChats")
            .whereField("participants", arrayContains: uid)
            .limit(to: max(1, min(chatLimit, 50)))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = Self.userFacingFirestoreError(error)
                        self.isLoading = false
                    }
                    print("[HomeStore] chats listener error: \(error)")
                    return
                }

                let docs = snapshot?.documents ?? []
                var items: [HomeChatSummary] = docs.compactMap { doc in
                    let data = doc.data()
                    let participants = data["participants"] as? [String] ?? []
                    let otherUid = (participants.first { $0 != uid } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if otherUid.isEmpty { return nil }

                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                    let lastText = (data["lastMessageText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    let lastSeenAt = Self.lastSeenDate(chatId: doc.documentID)
                    let isUnread: Bool
                    if let updatedAt {
                        isUnread = updatedAt > (lastSeenAt ?? .distantPast)
                    } else {
                        isUnread = false
                    }

                    return HomeChatSummary(
                        id: doc.documentID,
                        otherUid: otherUid,
                        otherName: self.nameCache[otherUid] ?? otherUid,
                        lastText: lastText,
                        updatedAt: updatedAt,
                        isUnread: isUnread
                    )
                }

                items.sort { (a, b) in
                    let da = a.updatedAt ?? .distantPast
                    let db = b.updatedAt ?? .distantPast
                    return da > db
                }

                Task { @MainActor in
                    self.chats = items
                    self.isLoading = false
                }

                Task { @MainActor in
                    self.prefetchNamesIfNeeded(otherUids: Set(items.map { $0.otherUid }))
                }
            }

        notesListener?.remove()
        notesListener = db.collection("notes")
            .order(by: "updatedAt", descending: true)
            .limit(to: max(1, min(noteLimit, 50)))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = Self.userFacingFirestoreError(error)
                        self.isLoading = false
                    }
                    print("[HomeStore] notes listener error: \(error)")
                    return
                }

                let docs = snapshot?.documents ?? []
                let items: [HomeNoteSummary] = docs.compactMap { doc in
                    let data = doc.data()
                    let title = (data["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if title.isEmpty { return nil }

                    let updatedAtSeconds = (data["updatedAt"] as? Int64) ?? Int64((data["updatedAt"] as? Int) ?? 0)
                    let updatedAt = updatedAtSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(updatedAtSeconds)) : nil
                    let updatedByName = (data["updatedByName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    return HomeNoteSummary(
                        id: doc.documentID,
                        title: title,
                        updatedAt: updatedAt,
                        updatedByName: updatedByName
                    )
                }

                Task { @MainActor in
                    self.notes = items
                    self.isLoading = false
                }
            }
        #else
        chats = []
        notes = []
        threads = []
        isLoading = false
        #endif

        threads = forumStore.threads
    }

    #if canImport(FirebaseFirestore)
    private func prefetchNamesIfNeeded(otherUids: Set<String>) {
        let missing = otherUids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && nameCache[$0] == nil }

        guard !missing.isEmpty else { return }

        for ouid in missing.prefix(15) {
            Task {
                do {
                    let doc = try await db.collection("users")
                        .document(ouid)
                        .collection("profile")
                        .document("main")
                        .getDocument()

                    let dn = (doc.data()?["displayName"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    await MainActor.run {
                        if !dn.isEmpty {
                            self.nameCache[ouid] = dn
                        }
                        self.chats = self.chats.map { c in
                            guard c.otherUid == ouid else { return c }
                            var copy = c
                            copy.otherName = dn.isEmpty ? copy.otherName : dn
                            return copy
                        }
                    }
                } catch {
                    print("[HomeStore] name prefetch failed for \(ouid): \(error)")
                }
            }
        }
    }
    #endif

    private static func userFacingFirestoreError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("requires an index") {
            return "Firestore: требуется индекс для запроса. Я убрал сортировку, но если ошибка осталась — опубликуй индекс в Firebase Console."
        }
        return raw
    }

    func refreshThreadsFromForumStore(_ forumStore: WikiForumStore) {
        threads = forumStore.threads
    }

    static func markChatSeen(chatId: String) {
        let key = "home_chat_last_seen_" + chatId
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    }

    static func lastSeenDate(chatId: String) -> Date? {
        let key = "home_chat_last_seen_" + chatId
        let v = UserDefaults.standard.double(forKey: key)
        if v <= 0 { return nil }
        return Date(timeIntervalSince1970: v)
    }
}
