import SwiftUI

struct GroupsSandboxView: View {
    @EnvironmentObject private var session: UserSessionStore
    @ObservedObject var friendsStore: FriendsStore
    @StateObject private var store = GroupsStore()

    @State private var isCreatePresented = false
    @State private var draftTitle = ""
    @State private var draftType: GroupType = .university

    var body: some View {
        NavigationStack {
            List {
                if store.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }

                if let error = store.errorMessage, !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(store.groups) { g in
                        NavigationLink {
                            GroupSandboxDetailView(group: g, friendsStore: friendsStore)
                        } label: {
                            GroupRow(title: g.title, subtitle: g.type.title)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await store.deleteGroup(groupId: g.id, myUid: session.effectiveUserId)
                                    await store.loadMyGroups(myUid: session.effectiveUserId)
                                }
                            } label: {
                                Text("Удалить")
                            }
                        }
                    }

                    if store.groups.isEmpty && !store.isLoading {
                        ContentUnavailableView(
                            "Нет групп",
                            systemImage: "person.3",
                            description: Text("Создай группу: курс, кафедра, коллеги")
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .navigationTitle("Группы")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftTitle = ""
                        draftType = .university
                        isCreatePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatePresented) {
                NavigationStack {
                    Form {
                        Section("Название") {
                            TextField("Например: Группа 7", text: $draftTitle)
                                .textInputAutocapitalization(.sentences)
                        }
                        Section("Тип") {
                            Picker("Тип", selection: $draftType) {
                                ForEach(GroupType.allCases) { t in
                                    Text(t.title).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .navigationTitle("Новая группа")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { isCreatePresented = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Создать") {
                                Task {
                                    let _ = await store.createGroup(myUid: session.effectiveUserId, title: draftTitle, type: draftType)
                                    await store.loadMyGroups(myUid: session.effectiveUserId)
                                    await MainActor.run { isCreatePresented = false }
                                }
                            }
                            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .task {
                await store.loadMyGroups(myUid: session.effectiveUserId)
            }
            .onChange(of: session.userId) { _, _ in
                Task { await store.loadMyGroups(myUid: session.effectiveUserId) }
            }
        }
    }
}

private struct GroupRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Группа" : title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    GroupsSandboxView(friendsStore: FriendsStore())
        .environmentObject(UserSessionStore())
}
