import SwiftUI
import PhotosUI

struct FriendsView: View {
    @ObservedObject var store: FriendsStore
    @EnvironmentObject private var session: UserSessionStore
    @State private var showAddSheet = false

    var body: some View {
        List {
            if store.friends.isEmpty {
                ContentUnavailableView("Нет друзей", systemImage: "person.2.slash", description: Text("Добавьте друзей, чтобы видеть их профили"))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(FriendRelation.allCases, id: \.self) { relation in
                let sectionFriends = store.friends.filter { $0.relation == relation }
                if !sectionFriends.isEmpty {
                    Section(relation.rawValue) {
                        ForEach(sectionFriends) { friend in
                            NavigationLink {
                                FriendProfileDetailView(friend: friend, store: store)
                            } label: {
                                HStack {
                                    if let img = friend.avatarUIImage {
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary.opacity(0.3))
                                    }
                                    VStack(alignment: .leading) {
                                        Text(friend.name)
                                            .font(.headline)
                                        if !friend.workPlace.isEmpty {
                                            Text(friend.workPlace)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            let toDelete = idx.map { sectionFriends[$0] }
                            for f in toDelete {
                                store.delete(f)
                                if let fid = f.uid, !fid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Task {
                                        await store.deleteFriendshipFromCloud(myUid: session.effectiveUserId, friendUid: fid)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Мои друзья")
        .toolbar {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFriendView(store: store)
        }
    }
}

struct AddFriendView: View {
    @ObservedObject var store: FriendsStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: UserSessionStore

    @State private var searchQuery = ""
    @State private var searchResults: [Friend] = []
    @State private var isSearching = false
    @State private var selectedFriend: Friend?
    @State private var selectedRelation: FriendRelation = .classmate

    var body: some View {
        NavigationStack {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск по имени", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 12, padding: nil)
                .padding(.horizontal)
                .padding(.top)

                if isSearching {
                    ProgressView()
                        .padding()
                } else if !searchResults.isEmpty {
                    List(searchResults) { friend in
                        Button {
                            selectedFriend = friend
                        } label: {
                            HStack {
                                if let img = friend.avatarUIImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary.opacity(0.3))
                                }
                                VStack(alignment: .leading) {
                                    Text(friend.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if !friend.workPlace.isEmpty {
                                        Text(friend.workPlace)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if !friend.email.isEmpty {
                                         Text(friend.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(SolarizedTheme.accentColor)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else if !searchQuery.isEmpty {
                    ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуйте другой запрос"))
                } else {
                    ContentUnavailableView("Поиск друзей", systemImage: "person.2.magnifyingglass", description: Text("Введите email или имя пользователя"))
                }
                
                Spacer()
            }
            .navigationTitle("Добавить друга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Зыкрыть") { dismiss() }
                }
            }
            .sheet(item: $selectedFriend) { friend in
                AssignRoleView(friend: friend) { relation in
                    var newFriend = friend
                    newFriend.relation = relation
                    store.add(newFriend)
                    Task {
                        if let fid = newFriend.uid, !fid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await store.upsertFriendshipToCloud(myUid: session.effectiveUserId, friendUid: fid)
                        }
                        await MainActor.run {
                            dismiss() // Dismiss AddFriendView
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            let results = await store.searchUsers(query: searchQuery)
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
}

struct AssignRoleView: View {
    let friend: Friend
    let onConfirm: (FriendRelation) -> Void
    @State private var relation: FriendRelation = .classmate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Выберите роль")
                .font(.headline)
                .padding(.top)

            HStack {
                if let img = friend.avatarUIImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                }
                VStack(alignment: .leading) {
                    Text(friend.name)
                        .font(.title3.bold())
                    Text(friend.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Picker("Роль", selection: $relation) {
                ForEach(FriendRelation.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.wheel)

            Button {
                onConfirm(relation)
            } label: {
                Text("Добавить")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(SolarizedTheme.accentColor)
                    .clipShape(Capsule())
            }
            .padding()
        }
        .padding()
    }
}

struct FriendProfileDetailView: View {
    let friend: Friend
    @ObservedObject var store: FriendsStore
    @EnvironmentObject private var session: UserSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    @State private var isDirectChatPresented: Bool = false

    var body: some View {
        ScrollView {
            ProfileCardView(
                displayName: friend.name,
                workPlace: friend.workPlace,
                studyPlace: friend.studyPlace,
                email: friend.email,
                avatarImage: friend.avatarUIImage,
                stats: [(friend.relation.rawValue, "Статус")],
                actionButtons: {
                    Button {
                        isDirectChatPresented = true
                    } label: {
                        Text("Написать сообщение")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(SolarizedTheme.accentColor)
                            .clipShape(Capsule())
                    }
                }
            )
            .padding()
        }
        .background(SolarizedTheme.backgroundColor)
        .navigationTitle(friend.name)
        .navigationDestination(isPresented: $isDirectChatPresented) {
            let uid = (friend.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if uid.isEmpty {
                Text("Нет UID пользователя")
                    .foregroundStyle(.secondary)
            } else {
                DirectChatView(otherUid: uid, otherName: friend.name)
            }
        }
        .toolbar {
            Button("Удалить", role: .destructive) {
                store.delete(friend)
                if let fid = friend.uid, !fid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await store.deleteFriendshipFromCloud(myUid: session.effectiveUserId, friendUid: fid)
                    }
                }
                dismiss()
            }
        }
        .background(SolarizedTheme.backgroundColor)
    }
}

#Preview {
    FriendsView(store: FriendsStore())
}
