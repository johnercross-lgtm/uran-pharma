import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct WikiForumThreadDTO: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var createdAt: Date?
    var createdByUid: String
    var createdByName: String
    var lastPostAt: Date?
    var lastPostText: String
}

struct WikiForumPostDTO: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var createdAt: Date?
    var fromUid: String
    var fromName: String
}

@MainActor
final class WikiForumStore: ObservableObject {
    @Published var threads: [WikiForumThreadDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var threadsListener: ListenerRegistration?
    private var postsListener: ListenerRegistration?
    #endif

    deinit {
        #if canImport(FirebaseFirestore)
        threadsListener?.remove()
        postsListener?.remove()
        #endif
    }

    func listenThreads(limit: Int = 200) {
        #if canImport(FirebaseFirestore)
        isLoading = true
        errorMessage = nil
        threadsListener?.remove()
        threadsListener = db.collection("wikiForumThreads")
            .order(by: "lastPostAt", descending: true)
            .limit(to: max(1, min(limit, 500)))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                let items = docs.compactMap { Self.mapThread($0) }
                Task { @MainActor in
                    self.threads = items
                    self.isLoading = false
                }
            }
        #else
        threads = []
        #endif
    }

    func stopListeningThreads() {
        #if canImport(FirebaseFirestore)
        threadsListener?.remove()
        threadsListener = nil
        #endif
    }

    func createThread(title: String, myUid: String, myName: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            let ref = db.collection("wikiForumThreads").document()
            let now = FieldValue.serverTimestamp()
            try await ref.setData([
                "title": t,
                "createdAt": now,
                "createdByUid": uid,
                "createdByName": name,
                "lastPostAt": now,
                "lastPostText": ""
            ], merge: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func deleteThread(threadId: String, myUid: String) async {
        let tid = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            let doc = try await db.collection("wikiForumThreads").document(tid).getDocument()
            let createdByUid = (doc.data()?["createdByUid"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard createdByUid == uid else { return }
            try await db.collection("wikiForumThreads").document(tid).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func listenPosts(threadId: String, limit: Int = 400, onUpdate: @escaping ([WikiForumPostDTO]) -> Void) {
        let tid = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else {
            onUpdate([])
            return
        }

        #if canImport(FirebaseFirestore)
        postsListener?.remove()
        postsListener = db.collection("wikiForumThreads")
            .document(tid)
            .collection("posts")
            .order(by: "createdAt", descending: false)
            .limit(toLast: max(1, min(limit, 1000)))
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                let items = docs.compactMap { Self.mapPost($0) }
                onUpdate(items)
            }
        #else
        onUpdate([])
        #endif
    }

    func stopListeningPosts() {
        #if canImport(FirebaseFirestore)
        postsListener?.remove()
        postsListener = nil
        #endif
    }

    func addPost(threadId: String, text: String, myUid: String, myName: String) async {
        let tid = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty, !t.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            let now = FieldValue.serverTimestamp()
            let threadRef = db.collection("wikiForumThreads").document(tid)
            try await threadRef.collection("posts").document().setData([
                "text": t,
                "createdAt": now,
                "fromUid": uid,
                "fromName": name
            ], merge: false)

            try await threadRef.setData([
                "lastPostAt": now,
                "lastPostText": t
            ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    private static func mapThread(_ doc: QueryDocumentSnapshot) -> WikiForumThreadDTO? {
        let data = doc.data()
        let title = (data["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let createdByUid = (data["createdByUid"] as? String ?? "")
        let createdByName = (data["createdByName"] as? String ?? "")
        let lastPostAt = (data["lastPostAt"] as? Timestamp)?.dateValue()
        let lastPostText = (data["lastPostText"] as? String ?? "")
        return WikiForumThreadDTO(
            id: doc.documentID,
            title: title,
            createdAt: createdAt,
            createdByUid: createdByUid,
            createdByName: createdByName,
            lastPostAt: lastPostAt,
            lastPostText: lastPostText
        )
    }

    private static func mapPost(_ doc: QueryDocumentSnapshot) -> WikiForumPostDTO? {
        let data = doc.data()
        let text = (data["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let fromUid = (data["fromUid"] as? String ?? "")
        let fromName = (data["fromName"] as? String ?? "")
        return WikiForumPostDTO(
            id: doc.documentID,
            text: text,
            createdAt: createdAt,
            fromUid: fromUid,
            fromName: fromName
        )
    }
}
