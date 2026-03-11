import Foundation

struct NoteFolder: Identifiable, Hashable {
    let id: String
    var title: String
    var sortOrder: Int
    var updatedAt: Int64
    var updatedByUid: String?
}

struct NoteItem: Identifiable, Hashable {
    let id: String
    var folderId: String
    var title: String
    var content: String
    var updatedAt: Int64
    var updatedByUid: String?
    var updatedByName: String?
}

struct NoteFeedItem: Identifiable, Hashable {
    var id: String { note.id }
    let note: NoteItem
    let folderTitle: String
}
