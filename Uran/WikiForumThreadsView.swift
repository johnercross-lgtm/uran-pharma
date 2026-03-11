import SwiftUI

struct WikiForumThreadsView: View {
    @EnvironmentObject private var session: UserSessionStore
    @StateObject private var store = WikiForumStore()

    @State private var isCreatePresented: Bool = false
    @State private var draftTitle: String = ""

    var body: some View {
        List {
            if store.isLoading {
                ProgressView()
                    .listRowBackground(Color.clear)
            }

            if let error = store.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }

            ForEach(store.threads) { th in
                NavigationLink {
                    WikiForumThreadDetailView(threadId: th.id, threadTitle: th.title)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(th.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SolarizedTheme.accentColor)
                            .lineLimit(2)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            let author = th.createdByName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !author.isEmpty {
                                Text(author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                let uid = th.createdByUid.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !uid.isEmpty {
                                    Text(String(uid.prefix(8)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let d = th.createdAt {
                                Text(d, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let last = th.lastPostAt {
                                Text(last, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        let preview = th.lastPostText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !preview.isEmpty {
                            Text(preview)
                                .font(.subheadline)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await store.deleteThread(threadId: th.id, myUid: session.effectiveUserId)
                        }
                    } label: {
                        Text("Удалить")
                    }
                }
            }

            if !store.isLoading, store.threads.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Форум пуст")
                        .font(.headline)
                    Text("Создай первую тему")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .refreshable {
            store.stopListeningThreads()
            store.listenThreads()
        }
        .scrollContentBackground(.hidden)
        .background(SolarizedTheme.backgroundColor)
        .navigationTitle("Форум")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                draftTitle = ""
                isCreatePresented = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $isCreatePresented) {
            NavigationStack {
                Form {
                    Section("Тема") {
                        TextField("Например: Расписание/вопрос", text: $draftTitle)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(SolarizedTheme.backgroundColor)
                .navigationTitle("Новая тема")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { isCreatePresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") {
                            Task {
                                await store.createThread(
                                    title: draftTitle,
                                    myUid: session.effectiveUserId,
                                    myName: session.displayName
                                )
                                await MainActor.run { isCreatePresented = false }
                            }
                        }
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .task {
            store.listenThreads()
        }
        .onDisappear {
            store.stopListeningThreads()
        }
    }
}

#Preview {
    NavigationStack {
        WikiForumThreadsView()
            .environmentObject(UserSessionStore())
    }
}
