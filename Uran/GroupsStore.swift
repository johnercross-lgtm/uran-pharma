import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum GroupType: String, Codable, CaseIterable, Identifiable {
    case university
    case college
    case work
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .university: return "Универ"
        case .college: return "Колледж"
        case .work: return "Работа"
        case .other: return "Другое"
        }
    }
}

enum GroupRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case admin
    case leader
    case member

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "Владелец"
        case .admin: return "Админ"
        case .leader: return "Староста"
        case .member: return "Участник"
        }
    }
}

struct GroupDTO: Identifiable, Codable, Hashable {
    var id: String
    var ownerUid: String
    var title: String
    var type: GroupType
    var createdAt: Date?
    var updatedAt: Date?
}

struct GroupMemberDTO: Identifiable, Codable, Hashable {
    var id: String // uid
    var role: GroupRole
    var subgroup: String
    var joinedAt: Date?
}

struct GroupBoardDTO: Identifiable, Codable, Hashable {
    var id: String
    var type: String
    var title: String
    var createdByUid: String
    var createdAt: Date?
    var updatedAt: Date?
}

struct GroupBoardItemDTO: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var done: Bool
    var assigneeUid: String
    var order: Int
    var updatedAt: Date?
    var updatedByUid: String
}

struct GroupPollDTO: Identifiable, Codable, Hashable {
    var id: String
    var question: String
    var options: [String]
    var createdByUid: String
    var createdAt: Date?
    var isClosed: Bool
}

struct GroupPollVoteDTO: Identifiable, Codable, Hashable {
    var id: String // uid
    var optionIndex: Int
    var votedAt: Date?
}

struct GroupMessageDTO: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var fromUid: String
    var createdAt: Date?
    var deliveredTo: [String]
    var seenBy: [String]
}

@MainActor
final class GroupsStore: ObservableObject {
    @Published var groups: [GroupDTO] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    #if canImport(FirebaseFirestore)
    private let db = Firestore.firestore()

    private var messagesListener: ListenerRegistration?

    private func groupMembershipDocRef(uid: String, groupId: String) -> DocumentReference {
        db.collection("groupMemberships")
            .document(uid)
            .collection("groups")
            .document(groupId)
    }

    private func userNotificationCollectionRef(uid: String) -> CollectionReference {
        db.collection("users")
            .document(uid)
            .collection("notifications")
    }
    #endif

    deinit {
        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        #endif
    }

    func fetchDisplayName(uid: String) async -> String? {
        let id = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        #if canImport(FirebaseFirestore)
        do {
            let doc = try await db
                .collection("users")
                .document(id)
                .collection("profile")
                .document("main")
                .getDocument()
            let name = (doc.data()?["displayName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    func deleteGroup(groupId: String, myUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid).delete()
        } catch {
        }

        do {
            try await groupMembershipDocRef(uid: uid, groupId: gid).delete()
        } catch {
        }
        #endif
    }

    func updateGroupTitle(groupId: String, title: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !t.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid).setData([
                "title": t,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func loadMyGroups(myUid: String) async {
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        isLoading = true
        errorMessage = nil
        do {
            var groupsById: [String: GroupDTO] = [:]

            // 1) Groups where I'm a member (via index)
            let membershipSnap = try await db.collection("groupMemberships")
                .document(uid)
                .collection("groups")
                .getDocuments()

            let groupIds = Set(membershipSnap.documents.compactMap { $0.documentID })
            for gid in groupIds {
                let doc = try await db.collection("groups").document(gid).getDocument()
                if let dto = Self.mapGroup(doc) {
                    groupsById[dto.id] = dto
                }
            }

            // 2) Groups where I'm owner (in case owner isn't in members due to legacy data)
            do {
                let ownerSnap = try await db.collection("groups")
                    .whereField("ownerUid", isEqualTo: uid)
                    .getDocuments()
                for doc in ownerSnap.documents {
                    if let dto = Self.mapGroup(doc) {
                        groupsById[dto.id] = dto
                    }
                }
            } catch {
                // If rules don't allow listing groups by ownerUid unless you're also a member,
                // treat this fallback as best-effort.
            }

            var items = Array(groupsById.values)
            items.sort { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
            groups = items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        #else
        groups = []
        #endif
    }

    func createGroup(myUid: String, title: String, type: GroupType) async -> String? {
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, !t.isEmpty else { return nil }

        #if canImport(FirebaseFirestore)
        do {
            let ref = db.collection("groups").document()
            let now = FieldValue.serverTimestamp()
            try await ref.setData([
                "ownerUid": uid,
                "title": t,
                "type": type.rawValue,
                "createdAt": now,
                "updatedAt": now
            ], merge: false)

            try await ref.collection("members").document(uid).setData([
                "uid": uid,
                "role": GroupRole.owner.rawValue,
                "subgroup": "",
                "joinedAt": now
            ], merge: false)

            try await groupMembershipDocRef(uid: uid, groupId: ref.documentID).setData([
                "groupId": ref.documentID,
                "uid": uid,
                "joinedAt": now
            ], merge: true)

            return ref.documentID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        #else
        return nil
        #endif
    }

    func loadMembers(groupId: String) async -> [GroupMemberDTO] {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty else { return [] }

        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db.collection("groups").document(gid).collection("members")
                .getDocuments()
            var members: [GroupMemberDTO] = []
            for doc in snap.documents {
                if let dto = Self.mapMember(doc) {
                    members.append(dto)
                }
            }
            members.sort { $0.id < $1.id }
            return members
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
        #else
        return []
        #endif
    }

    func listenMessages(groupId: String, limit: Int = 200, onUpdate: @escaping ([GroupMessageDTO]) -> Void) {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty else {
            onUpdate([])
            return
        }

        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        messagesListener = db.collection("groups")
            .document(gid)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
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

    func stopListeningMessages() {
        #if canImport(FirebaseFirestore)
        messagesListener?.remove()
        messagesListener = nil
        #endif
    }

    func sendMessage(groupId: String, myUid: String, text: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !uid.isEmpty, !t.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups")
                .document(gid)
                .collection("messages")
                .document()
                .setData([
                    "text": t,
                    "fromUid": uid,
                    "createdAt": FieldValue.serverTimestamp(),
                    "deliveredTo": [uid],
                    "seenBy": [uid]
                ], merge: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func markMessageDelivered(groupId: String, messageId: String, myUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !mid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups")
                .document(gid)
                .collection("messages")
                .document(mid)
                .setData([
                    "deliveredTo": FieldValue.arrayUnion([uid])
                ], merge: true)
        } catch {
        }
        #endif
    }

    func markMessageSeen(groupId: String, messageId: String, myUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !mid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups")
                .document(gid)
                .collection("messages")
                .document(mid)
                .setData([
                    "seenBy": FieldValue.arrayUnion([uid]),
                    "deliveredTo": FieldValue.arrayUnion([uid])
                ], merge: true)
        } catch {
        }
        #endif
    }

    func upsertMember(groupId: String, memberUid: String, role: GroupRole, subgroup: String, actorUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = memberUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let actor = actorUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid).collection("members").document(uid)
                .setData([
                    "uid": uid,
                    "role": role.rawValue,
                    "subgroup": subgroup.trimmingCharacters(in: .whitespacesAndNewlines),
                    "joinedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            try await groupMembershipDocRef(uid: uid, groupId: gid).setData([
                "groupId": gid,
                "uid": uid,
                "joinedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
        }

        if !actor.isEmpty, actor != uid {
            do {
                let groupDoc = try await db.collection("groups").document(gid).getDocument()
                let groupTitle = (groupDoc.data()?["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                try await userNotificationCollectionRef(uid: uid).document().setData([
                    "type": "group_added",
                    "groupId": gid,
                    "groupTitle": groupTitle,
                    "fromUid": actor,
                    "createdAt": FieldValue.serverTimestamp(),
                    "isRead": false
                ], merge: false)
            } catch {
            }
        }
        #endif
    }

    func deleteMember(groupId: String, memberUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = memberUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid).collection("members").document(uid).delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            try await groupMembershipDocRef(uid: uid, groupId: gid).delete()
        } catch {
        }
        #endif
    }

    func ensureDefaultChecklistBoard(groupId: String, myUid: String) async -> GroupBoardDTO? {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !uid.isEmpty else { return nil }

        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db.collection("groups").document(gid).collection("boards")
                .whereField("type", isEqualTo: "checklist")
                .limit(to: 1)
                .getDocuments()

            if let first = snap.documents.first, let dto = Self.mapBoard(first) {
                return dto
            }

            let ref = db.collection("groups").document(gid).collection("boards").document()
            let now = FieldValue.serverTimestamp()
            try await ref.setData([
                "type": "checklist",
                "title": "Задачи",
                "createdByUid": uid,
                "createdAt": now,
                "updatedAt": now
            ], merge: false)

            let doc = try await ref.getDocument()
            return Self.mapBoard(doc)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        #else
        return nil
        #endif
    }

    func loadChecklistItems(groupId: String, boardId: String) async -> [GroupBoardItemDTO] {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bid = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !bid.isEmpty else { return [] }

        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db.collection("groups").document(gid)
                .collection("boards").document(bid)
                .collection("items")
                .order(by: "order", descending: false)
                .getDocuments()

            var items: [GroupBoardItemDTO] = []
            for doc in snap.documents {
                if let dto = Self.mapBoardItem(doc) {
                    items.append(dto)
                }
            }
            return items
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
        #else
        return []
        #endif
    }

    func addChecklistItem(groupId: String, boardId: String, myUid: String, text: String, assigneeUid: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bid = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !bid.isEmpty, !uid.isEmpty, !t.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            let itemsRef = db.collection("groups").document(gid)
                .collection("boards").document(bid)
                .collection("items")

            let countSnap = try await itemsRef.getDocuments()
            let nextOrder = countSnap.documents.count

            try await itemsRef.document().setData([
                "text": t,
                "done": false,
                "assigneeUid": assigneeUid.trimmingCharacters(in: .whitespacesAndNewlines),
                "order": nextOrder,
                "updatedAt": FieldValue.serverTimestamp(),
                "updatedByUid": uid
            ], merge: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func setChecklistItemDone(groupId: String, boardId: String, itemId: String, myUid: String, done: Bool) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bid = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        let iid = itemId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !bid.isEmpty, !iid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid)
                .collection("boards").document(bid)
                .collection("items").document(iid)
                .setData([
                    "done": done,
                    "updatedAt": FieldValue.serverTimestamp(),
                    "updatedByUid": uid
                ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func deleteChecklistItem(groupId: String, boardId: String, itemId: String) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let bid = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        let iid = itemId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !bid.isEmpty, !iid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid)
                .collection("boards").document(bid)
                .collection("items").document(iid)
                .delete()
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func createPoll(groupId: String, myUid: String, question: String, options: [String]) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !gid.isEmpty, !uid.isEmpty, !q.isEmpty, opts.count >= 2 else { return }

        #if canImport(FirebaseFirestore)
        do {
            let now = FieldValue.serverTimestamp()
            try await db.collection("groups").document(gid)
                .collection("polls").document()
                .setData([
                    "question": q,
                    "options": opts,
                    "createdByUid": uid,
                    "createdAt": now,
                    "isClosed": false
                ], merge: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func loadPolls(groupId: String) async -> [GroupPollDTO] {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty else { return [] }

        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db.collection("groups").document(gid)
                .collection("polls")
                .getDocuments()

            var polls: [GroupPollDTO] = []
            for doc in snap.documents {
                if let dto = Self.mapPoll(doc) {
                    polls.append(dto)
                }
            }
            polls.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            return polls
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
        #else
        return []
        #endif
    }

    func vote(groupId: String, pollId: String, myUid: String, optionIndex: Int) async {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = pollId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !pid.isEmpty, !uid.isEmpty else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await db.collection("groups").document(gid)
                .collection("polls").document(pid)
                .collection("votes").document(uid)
                .setData([
                    "optionIndex": optionIndex,
                    "votedAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func loadVotes(groupId: String, pollId: String) async -> [GroupPollVoteDTO] {
        let gid = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = pollId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty, !pid.isEmpty else { return [] }

        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db.collection("groups").document(gid)
                .collection("polls").document(pid)
                .collection("votes")
                .getDocuments()

            var votes: [GroupPollVoteDTO] = []
            for doc in snap.documents {
                if let dto = Self.mapVote(doc) {
                    votes.append(dto)
                }
            }
            return votes
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
        #else
        return []
        #endif
    }

    #if canImport(FirebaseFirestore)
    private static func mapGroup(_ doc: QueryDocumentSnapshot) -> GroupDTO? {
        let data = doc.data()
        guard let ownerUid = data["ownerUid"] as? String else { return nil }
        let title = data["title"] as? String ?? ""
        let typeRaw = data["type"] as? String ?? GroupType.other.rawValue
        let type = GroupType(rawValue: typeRaw) ?? .other
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return GroupDTO(id: doc.documentID, ownerUid: ownerUid, title: title, type: type, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func mapGroup(_ doc: DocumentSnapshot) -> GroupDTO? {
        guard let data = doc.data(), let ownerUid = data["ownerUid"] as? String else { return nil }
        let title = data["title"] as? String ?? ""
        let typeRaw = data["type"] as? String ?? GroupType.other.rawValue
        let type = GroupType(rawValue: typeRaw) ?? .other
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return GroupDTO(id: doc.documentID, ownerUid: ownerUid, title: title, type: type, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func mapMember(_ doc: QueryDocumentSnapshot) -> GroupMemberDTO? {
        let data = doc.data()
        let roleRaw = data["role"] as? String ?? GroupRole.member.rawValue
        let role = GroupRole(rawValue: roleRaw) ?? .member
        let subgroup = data["subgroup"] as? String ?? ""
        let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue()
        return GroupMemberDTO(id: doc.documentID, role: role, subgroup: subgroup, joinedAt: joinedAt)
    }

    private static func mapBoard(_ doc: QueryDocumentSnapshot) -> GroupBoardDTO? {
        let data = doc.data()
        let type = data["type"] as? String ?? ""
        let title = data["title"] as? String ?? ""
        let createdByUid = data["createdByUid"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return GroupBoardDTO(id: doc.documentID, type: type, title: title, createdByUid: createdByUid, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func mapBoard(_ doc: DocumentSnapshot) -> GroupBoardDTO? {
        guard let data = doc.data() else { return nil }
        let type = data["type"] as? String ?? ""
        let title = data["title"] as? String ?? ""
        let createdByUid = data["createdByUid"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return GroupBoardDTO(id: doc.documentID, type: type, title: title, createdByUid: createdByUid, createdAt: createdAt, updatedAt: updatedAt)
    }

    private static func mapBoardItem(_ doc: QueryDocumentSnapshot) -> GroupBoardItemDTO? {
        let data = doc.data()
        let text = data["text"] as? String ?? ""
        let done = data["done"] as? Bool ?? false
        let assigneeUid = data["assigneeUid"] as? String ?? ""
        let order = data["order"] as? Int ?? 0
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let updatedByUid = data["updatedByUid"] as? String ?? ""
        return GroupBoardItemDTO(id: doc.documentID, text: text, done: done, assigneeUid: assigneeUid, order: order, updatedAt: updatedAt, updatedByUid: updatedByUid)
    }

    private static func mapPoll(_ doc: QueryDocumentSnapshot) -> GroupPollDTO? {
        let data = doc.data()
        let question = data["question"] as? String ?? ""
        let options = data["options"] as? [String] ?? []
        let createdByUid = data["createdByUid"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let isClosed = data["isClosed"] as? Bool ?? false
        return GroupPollDTO(id: doc.documentID, question: question, options: options, createdByUid: createdByUid, createdAt: createdAt, isClosed: isClosed)
    }

    private static func mapVote(_ doc: QueryDocumentSnapshot) -> GroupPollVoteDTO? {
        let data = doc.data()
        let optionIndex = data["optionIndex"] as? Int ?? -1
        let votedAt = (data["votedAt"] as? Timestamp)?.dateValue()
        return GroupPollVoteDTO(id: doc.documentID, optionIndex: optionIndex, votedAt: votedAt)
    }

    private static func mapMessage(_ doc: QueryDocumentSnapshot) -> GroupMessageDTO? {
        let data = doc.data()
        let text = data["text"] as? String ?? ""
        let fromUid = data["fromUid"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let deliveredTo = data["deliveredTo"] as? [String] ?? []
        let seenBy = data["seenBy"] as? [String] ?? []
        return GroupMessageDTO(
            id: doc.documentID,
            text: text,
            fromUid: fromUid,
            createdAt: createdAt,
            deliveredTo: deliveredTo,
            seenBy: seenBy
        )
    }
    #endif
}
