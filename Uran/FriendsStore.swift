import Foundation
import UIKit
import SwiftUI
import Combine

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum FriendRelation: String, CaseIterable, Codable, Identifiable {


// ... (existing code)


    case classmate = "Одногруппник"
    case coursemate = "Сокурсник"
    case colleague = "Коллега"
    case friend = "Друг"

    var id: String { rawValue }
}

struct Friend: Identifiable, Codable {
    let id: UUID
    var uid: String? // Firebase User ID
    var name: String
    var relation: FriendRelation
    var workPlace: String
    var studyPlace: String
    var email: String
    var avatarBase64: String

    var avatarUIImage: UIImage? {
        guard !avatarBase64.isEmpty, let data = Data(base64Encoded: avatarBase64) else { return nil }
        return UIImage(data: data)
    }

    init(id: UUID = UUID(), uid: String? = nil, name: String, relation: FriendRelation, workPlace: String = "", studyPlace: String = "", email: String = "", avatarBase64: String = "") {
        self.id = id
        self.uid = uid
        self.name = name
        self.relation = relation
        self.workPlace = workPlace
        self.studyPlace = studyPlace
        self.email = email
        self.avatarBase64 = avatarBase64
    }
}

@MainActor
class FriendsStore: ObservableObject {
    @Published var friends: [Friend] = []
    
    private let defaultsKey = "uran_friends_v1"

    init() {
        load()
    }

    func add(_ friend: Friend) {
        friends.append(friend)
        save()
    }

    func delete(_ friend: Friend) {
        friends.removeAll { $0.id == friend.id }
        save()
    }

    func update(_ friend: Friend) {
        if let idx = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[idx] = friend
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        }
    }

    func searchUsers(query: String) async -> [Friend] {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        var results: [Friend] = []
        let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowerQuery.isEmpty else { return [] }

        // We search in "profile" collection group since structure is users/{uid}/profile/main
        // Note: This requires a composite index if we sort, but for simple equality/prefix it might work with single index.
        do {
            let nameQuery = try await db.collectionGroup("profile")
                .whereField("displayNameLower", isGreaterThanOrEqualTo: lowerQuery)
                .whereField("displayNameLower", isLessThan: lowerQuery + "\u{f8ff}")
                .getDocuments()

            for doc in nameQuery.documents {
                if let friend = mapDocumentToFriend(doc) {
                    if !results.contains(where: { $0.uid == friend.uid }) {
                        results.append(friend)
                    }
                }
            }
        } catch {
            print("Error searching users: \(error)")
        }
        
        return results
        #else
        // Stub for previews/non-firebase
        return []
        #endif
    }

    func upsertFriendshipToCloud(myUid: String, friendUid: String) async {
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let fid = friendUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, !fid.isEmpty, fid != uid else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await Firestore.firestore()
                .collection("friendships")
                .document(uid)
                .collection("friends")
                .document(fid)
                .setData([
                    "uid": fid,
                    "createdAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            print("upsertFriendshipToCloud error: \(error)")
        }
        #endif
    }

    func deleteFriendshipFromCloud(myUid: String, friendUid: String) async {
        let uid = myUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let fid = friendUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, !fid.isEmpty, fid != uid else { return }

        #if canImport(FirebaseFirestore)
        do {
            try await Firestore.firestore()
                .collection("friendships")
                .document(uid)
                .collection("friends")
                .document(fid)
                .delete()
        } catch {
            print("deleteFriendshipFromCloud error: \(error)")
        }
        #endif
    }
    
    #if canImport(FirebaseFirestore)
    private func mapDocumentToFriend(_ doc: QueryDocumentSnapshot) -> Friend? {
        let data = doc.data()
        // The doc ID is "main", so we can't get uid from .documentID usually.
        // But in collectionGroup query, .reference.parent.parent?.documentID might be the user ID?
        // users/{uid}/profile/main
        // ref: .../users/UID/profile/main
        // parent: .../users/UID/profile
        // parent.parent: .../users/UID  <- This is the DocumentReference for user.
        
        let uid = doc.reference.parent.parent?.documentID ?? ""
        guard !uid.isEmpty else { return nil }
        
        let name = data["displayName"] as? String ?? "User"
        let work = data["workPlace"] as? String ?? ""
        let study = data["studyPlace"] as? String ?? ""
        let em = data["email"] as? String ?? "" // Assuming email is saved in profile
        let ava = data["avatarBase64"] as? String ?? ""
        
        return Friend(uid: uid, name: name, relation: .friend, workPlace: work, studyPlace: study, email: em, avatarBase64: ava)
    }
    #endif
}
