import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct DirectChatMessageDTO: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var fromUid: String
    var createdAt: Date?
    var deliveredTo: [String]
    var seenBy: [String]
}

@MainActor
final class DirectChatStore: ObservableObject {
    @Published var errorMessage: String?

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()
    private var messagesListener: ListenerRegistration?
    #endif

    deinit {
        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        #endif
    }

    static func chatId(a: String, b: String) -> String {
        let a1 = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b1 = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a1 <= b1 { return a1 + "_" + b1 }
        return b1 + "_" + a1
    }

    func ensureChat(chatId: String, myUid: String, otherUid: String) async {
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let ouid = otherUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !uid.isEmpty, !ouid.isEmpty, uid != ouid else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("directChats")
                .document(cid)
                .setData([
                    "participants": [uid, ouid],
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
            print("ensureChat error: \(error)")
        }
        #endif
    }

    func listenMessages(chatId: String, limit: Int = 200, onUpdate: @escaping ([DirectChatMessageDTO]) -> Void) {
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else {
            onUpdate([])
            return
        }

        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        messagesListener = db.collection("directChats")
            .document(cid)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
                    print("listenMessages error: \(error)")
                    return
                }

                let docs = snapshot?.documents ?? []
                let items = docs.compactMap { Self.mapMessage($0) }
                onUpdate(items)
            }
        #else
        onUpdate([])
        #endif
    }

    func stopListening() {
        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        messagesListener = nil
        #endif
    }

    func sendMessage(chatId: String, myUid: String, otherUid: String, text: String) async {
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let ouid = otherUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !uid.isEmpty, !ouid.isEmpty, !t.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            let chatRef = db.collection("directChats").document(cid)
            let now = FieldValue.serverTimestamp()

            try await chatRef.setData([
                "participants": [uid, ouid],
                "updatedAt": now,
                "lastMessageText": t
            ], merge: true)

            try await chatRef.collection("messages").document().setData([
                "text": t,
                "fromUid": uid,
                "createdAt": now,
                "deliveredTo": [uid],
                "seenBy": [uid]
            ], merge: false)
        } catch {
            errorMessage = error.localizedDescription
            print("sendMessage error: \(error)")
        }
        #endif
    }

    func markDelivered(chatId: String, messageId: String, myUid: String) async {
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !mid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("directChats")
                .document(cid)
                .collection("messages")
                .document(mid)
                .setData([
                    "deliveredTo": FieldValue.arrayUnion([uid])
                ], merge: true)
        } catch {
            print("markDelivered error: \(error)")
        }
        #endif
    }

    func markSeen(chatId: String, messageId: String, myUid: String) async {
        let cid = chatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !mid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("directChats")
                .document(cid)
                .collection("messages")
                .document(mid)
                .setData([
                    "seenBy": FieldValue.arrayUnion([uid]),
                    "deliveredTo": FieldValue.arrayUnion([uid])
                ], merge: true)
        } catch {
            print("markSeen error: \(error)")
        }
        #endif
    }

    private static func mapMessage(_ doc: QueryDocumentSnapshot) -> DirectChatMessageDTO? {
        let data = doc.data()
        let text = data["text"] as? String ?? ""
        let fromUid = data["fromUid"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let deliveredTo = data["deliveredTo"] as? [String] ?? []
        let seenBy = data["seenBy"] as? [String] ?? []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return DirectChatMessageDTO(id: doc.documentID, text: text, fromUid: fromUid, createdAt: createdAt, deliveredTo: deliveredTo, seenBy: seenBy)
    }
}
