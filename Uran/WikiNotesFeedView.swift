import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct WikiNotesFeedView: View {
    let repository: PharmaRepository

    @EnvironmentObject private var session: UserSessionStore

    @State private var items: [NoteFeedItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var searchText: String = ""

    @State private var isCreatePresented: Bool = false
    @State private var draftTitle: String = ""
    @State private var draftContent: String = ""
    @State private var createError: String?

    @State private var isEditPresented: Bool = false
    @State private var editNoteId: String?
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editError: String?

    @State private var deleteNoteId: String?
    @State private var isDeleteConfirmPresented: Bool = false

    @State private var authorNames: [String: String] = [:]

    init(repository: PharmaRepository) {
        self.repository = repository
    }

    private func beginEdit(noteId: String) {
        do {
            let note = try repository.loadNote(noteId: noteId)
            editNoteId = noteId
            editTitle = note.title
            editContent = note.content
            editError = nil
            isEditPresented = true
        } catch {
            editError = error.localizedDescription
            editNoteId = noteId
            editTitle = ""
            editContent = ""
            isEditPresented = true
        }
    }

    private func saveEdit() async {
        guard let editNoteId else { return }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && content.isEmpty { return }

        do {
            editError = nil
            let folderId = try ensureWikiFolderId()
            _ = try repository.upsertNote(
                id: editNoteId,
                folderId: folderId,
                title: title,
                content: content,
                updatedByUid: session.effectiveUserId,
                updatedByName: session.displayName
            )

#if canImport(FirebaseFirestore)
            let note = try repository.loadNote(noteId: editNoteId)
            await repository.upsertNoteToCloud(
                noteId: note.id,
                folderId: note.folderId,
                title: note.title,
                content: note.content,
                updatedAt: note.updatedAt,
                updatedByUid: session.effectiveUserId,
                updatedByName: session.displayName
            )
#endif

            await MainActor.run {
                isEditPresented = false
                self.editNoteId = nil
                loadLocal(query: nil)
            }
        } catch {
            await MainActor.run {
                editError = error.localizedDescription
            }
        }
    }

    private func deleteNote(noteId: String) async {
        do {
            try repository.deleteNote(noteId: noteId)
#if canImport(FirebaseFirestore)
            await repository.deleteNoteFromCloud(noteId: noteId, createdByUid: session.effectiveUserId)
#endif
            await MainActor.run {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                loadLocal(query: q.isEmpty ? nil : q)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLocal(query: String?) {
        isLoading = true
        errorMessage = nil
        do {
            items = try repository.listNoteFeed(query: query)
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func syncAndReload() async {
        await repository.syncNotesFromCloud()
#if canImport(FirebaseFirestore)
        await repository.pushNotesToCloud(updatedByUid: session.effectiveUserId)
#endif
        await MainActor.run {
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            loadLocal(query: q.isEmpty ? nil : q)
        }

        await refreshAuthorNamesIfNeeded()
    }

    private func displayName(for uid: String) -> String? {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed == session.effectiveUserId {
            let dn = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dn.isEmpty { return dn }
        }
        return authorNames[trimmed]
    }

    private func refreshAuthorNamesIfNeeded() async {
#if canImport(FirebaseFirestore)
        let uids = Set(items.compactMap { ($0.note.updatedByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty && authorNames[$0] == nil && $0 != session.effectiveUserId }
        if uids.isEmpty { return }

        await withTaskGroup(of: (String, String?).self) { group in
            for uid in uids {
                group.addTask {
                    do {
                        let doc = try await FirebaseFirestore.Firestore.firestore()
                            .collection("users")
                            .document(uid)
                            .collection("profile")
                            .document("main")
                            .getDocument()
                        let dn = (doc.data()?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (uid, (dn?.isEmpty ?? true) ? nil : dn)
                    } catch {
                        return (uid, nil)
                    }
                }
            }

            var updates: [String: String] = [:]
            for await (uid, dn) in group {
                if let dn {
                    updates[uid] = dn
                }
            }

            if !updates.isEmpty {
                await MainActor.run {
                    for (k, v) in updates { authorNames[k] = v }
                }
            }
        }
#endif
    }

    private func ensureWikiFolderId() throws -> String {
        let folders = try repository.listNoteFolders()
        if let existing = folders.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == "Вики" }) {
            return existing.id
        }
        return try repository.upsertNoteFolder(id: nil, title: "Вики", sortOrder: 0, updatedByUid: session.effectiveUserId)
    }

    private func createNote() async {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && content.isEmpty { return }

        do {
            createError = nil
            let folderId = try ensureWikiFolderId()
            let noteId = try repository.upsertNote(
                id: nil,
                folderId: folderId,
                title: title,
                content: content,
                updatedByUid: session.effectiveUserId,
                updatedByName: session.displayName
            )

#if canImport(FirebaseFirestore)
            let note = try repository.loadNote(noteId: noteId)
            await repository.upsertNoteToCloud(
                noteId: note.id,
                folderId: note.folderId,
                title: note.title,
                content: note.content,
                updatedAt: note.updatedAt,
                updatedByUid: session.effectiveUserId,
                updatedByName: session.displayName,
                createdByUid: session.effectiveUserId
            )
#endif

            await MainActor.run {
                draftTitle = ""
                draftContent = ""
                isCreatePresented = false
                loadLocal(query: nil)
            }
        } catch {
            await MainActor.run {
                createError = error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                SolarizedTheme.backgroundColor
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Раздел со структурированными медицинскими статьями и знаниями. Пользователи могут сами создавать и редактировать материалы, формируя общую базу знаний и профессиональную среду.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Group {
                        if isLoading {
                            ProgressView()
                        } else {
                            List {
                                if let errorMessage, !errorMessage.isEmpty {
                                    Text(errorMessage)
                                        .foregroundStyle(.red)
                                        .listRowBackground(Color.clear)
                                }

                                ForEach(items) { item in
                                    let uid = (item.note.updatedByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let canManage = !uid.isEmpty && uid == session.effectiveUserId
                                    NavigationLink {
                                        let dn = uid.isEmpty ? nil : displayName(for: uid)
                                        WikiNoteDetailView(item: item, authorName: dn)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            let title = item.note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                                            Text(title.isEmpty ? "Без названия" : title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)

                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                let d = Date(timeIntervalSince1970: Double(item.note.updatedAt))
                                                Text(d, format: .dateTime.day().month().year().hour().minute())
                                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                    .foregroundStyle(.secondary)

                                                let uid = (item.note.updatedByUid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                                let storedName = (item.note.updatedByName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                                if !storedName.isEmpty {
                                                    Text("by \(storedName)")
                                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                } else if !uid.isEmpty {
                                                    let dn = displayName(for: uid)
                                                    Text("by \(dn ?? String(uid.prefix(8)))")
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

                                            let preview = item.note.content.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !preview.isEmpty {
                                                Text(preview)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(14)
                                        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .contextMenu {
                                        if canManage {
                                            Button("Редактировать") {
                                                beginEdit(noteId: item.note.id)
                                            }
                                            Button("Удалить", role: .destructive) {
                                                deleteNoteId = item.note.id
                                                isDeleteConfirmPresented = true
                                            }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if canManage {
                                            Button(role: .destructive) {
                                                deleteNoteId = item.note.id
                                                isDeleteConfirmPresented = true
                                            } label: {
                                                Text("Удалить")
                                            }
                                        }
                                    }
                                }
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .listStyle(.insetGrouped)
                            .refreshable {
                                await syncAndReload()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Вики")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: searchText) { _, newValue in
                let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                loadLocal(query: q.isEmpty ? nil : q)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WikiForumThreadsView()
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createError = nil
                        draftTitle = ""
                        draftContent = ""
                        isCreatePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .confirmationDialog(
                "Удалить запись?",
                isPresented: $isDeleteConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let deleteNoteId {
                        Task { await deleteNote(noteId: deleteNoteId) }
                    }
                    deleteNoteId = nil
                }
                Button("Отмена", role: .cancel) {
                    deleteNoteId = nil
                }
            }
            .sheet(isPresented: $isCreatePresented) {
                NavigationStack {
                    Form {
                        if let createError, !createError.isEmpty {
                            Text(createError)
                                .foregroundStyle(.red)
                        }

                        TextField("Заголовок", text: $draftTitle)

                        TextEditor(text: $draftContent)
                            .frame(minHeight: 320)
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Новая запись")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Отмена") {
                                isCreatePresented = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Сохранить") {
                                Task { await createNote() }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditPresented) {
                NavigationStack {
                    Form {
                        if let editError, !editError.isEmpty {
                            Text(editError)
                                .foregroundStyle(.red)
                        }

                        TextField("Заголовок", text: $editTitle)

                        TextEditor(text: $editContent)
                            .frame(minHeight: 320)
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Редактировать")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Отмена") {
                                isEditPresented = false
                                editNoteId = nil
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Сохранить") {
                                Task { await saveEdit() }
                            }
                            .disabled(editNoteId == nil)
                        }
                    }
                }
            }
            .task {
                loadLocal(query: nil)
                await refreshAuthorNamesIfNeeded()
                await syncAndReload()
            }
        }
    }
}
