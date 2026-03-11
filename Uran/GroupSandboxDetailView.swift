import SwiftUI

struct GroupSandboxDetailView: View {
    @EnvironmentObject private var session: UserSessionStore

    let group: GroupDTO
    @ObservedObject var friendsStore: FriendsStore

    @StateObject private var store = GroupsStore()

    @State private var members: [GroupMemberDTO] = []

    @State private var nameCache: [String: String] = [:]

    @State private var selectedTab: Tab = .members

    @State private var checklistBoardId: String?
    @State private var checklistItems: [GroupBoardItemDTO] = []
    @State private var newChecklistText: String = ""

    @State private var polls: [GroupPollDTO] = []

    @State private var isCreatePollPresented: Bool = false
    @State private var draftQuestion: String = ""
    @State private var draftOption1: String = ""
    @State private var draftOption2: String = ""

    @State private var isAddMemberPresented: Bool = false
    @State private var addMemberRole: GroupRole = .member
    @State private var addMemberSubgroup: String = ""

    @State private var isEditTitlePresented: Bool = false
    @State private var draftGroupTitle: String = ""
    @State private var groupTitle: String

    @State private var messages: [GroupMessageDTO] = []
    @State private var newMessageText: String = ""

    init(group: GroupDTO, friendsStore: FriendsStore) {
        self.group = group
        self.friendsStore = friendsStore
        _groupTitle = State(initialValue: group.title)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case members
        case checklist
        case polls
        case chat

        var id: String { rawValue }

        var title: String {
            switch self {
            case .members: return "Люди"
            case .checklist: return "Задачи"
            case .polls: return "Голосование"
            case .chat: return "Чат"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedTab {
            case .members:
                membersTab
            case .checklist:
                checklistTab
            case .polls:
                pollsTab
            case .chat:
                chatTab
            }
        }
        .navigationTitle(groupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                draftGroupTitle = groupTitle
                isEditTitlePresented = true
            } label: {
                Image(systemName: "pencil")
            }

            if selectedTab == .polls {
                Button {
                    draftQuestion = ""
                    draftOption1 = ""
                    draftOption2 = ""
                    isCreatePollPresented = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            if selectedTab == .members {
                Button {
                    addMemberRole = .member
                    addMemberSubgroup = ""
                    isAddMemberPresented = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isEditTitlePresented) {
            NavigationStack {
                Form {
                    Section("Название") {
                        TextField("Название", text: $draftGroupTitle)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(SolarizedTheme.backgroundColor)
                .navigationTitle("Редактировать")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { isEditTitlePresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            let t = draftGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            Task {
                                await store.updateGroupTitle(groupId: group.id, title: t)
                                await MainActor.run {
                                    groupTitle = t
                                    isEditTitlePresented = false
                                }
                            }
                        }
                        .disabled(draftGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $isCreatePollPresented) {
            NavigationStack {
                Form {
                    Section("Вопрос") {
                        TextField("Например: Перенести пару?", text: $draftQuestion)
                    }
                    Section("Варианты") {
                        TextField("Вариант 1", text: $draftOption1)
                        TextField("Вариант 2", text: $draftOption2)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(SolarizedTheme.backgroundColor)
                .navigationTitle("Новое голосование")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { isCreatePollPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") {
                            Task {
                                await store.createPoll(
                                    groupId: group.id,
                                    myUid: session.effectiveUserId,
                                    question: draftQuestion,
                                    options: [draftOption1, draftOption2]
                                )
                                await reloadPolls()
                                await MainActor.run { isCreatePollPresented = false }
                            }
                        }
                        .disabled(draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .task {
            await reloadAll()
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .chat {
                startChatListenerIfNeeded()
            } else {
                store.stopListeningMessages()
            }
        }
        .onDisappear {
            store.stopListeningMessages()
        }
        .sheet(isPresented: $isAddMemberPresented) {
            NavigationStack {
                Form {
                    Section("Пользователь") {
                        if let error = store.errorMessage, !error.isEmpty {
                            Text(error)
                                .foregroundStyle(.red)
                                .listRowBackground(Color.clear)
                        }

                        if friendsStore.friends.isEmpty {
                            Text("Добавь друзей, чтобы выбирать из списка")
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section("Роль") {
                        Picker("Роль", selection: $addMemberRole) {
                            ForEach(GroupRole.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Подгруппа") {
                        TextField("Подгруппа", text: $addMemberSubgroup)
                    }

                    Section("Друзья") {
                        if friendsStore.friends.isEmpty {
                            Text("Список друзей пуст")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(friendsStore.friends) { f in
                                let uid = (f.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                if uid.isEmpty {
                                    HStack {
                                        Text(f.name)
                                        Spacer()
                                        Text("no uid")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        Task {
                                            await store.upsertMember(
                                                groupId: group.id,
                                                memberUid: uid,
                                                role: addMemberRole,
                                                subgroup: addMemberSubgroup,
                                                actorUid: session.effectiveUserId
                                            )
                                            await reloadMembers()
                                            await MainActor.run { isAddMemberPresented = false }
                                        }
                                    } label: {
                                        HStack {
                                            Text(f.name)
                                            Spacer()
                                            Text(String(uid.prefix(6)))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(SolarizedTheme.backgroundColor)
                .navigationTitle("Добавить участника")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { isAddMemberPresented = false }
                    }
                }
            }
        }
    }

    private var membersTab: some View {
        List {
            if let error = store.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }

            Section("Участники") {
                ForEach(members) { m in
                    MemberRow(title: displayName(for: m.id), subtitle: m.id, member: m) { newRole, newSubgroup in
                        Task {
                            await store.upsertMember(
                                groupId: group.id,
                                memberUid: m.id,
                                role: newRole,
                                subgroup: newSubgroup,
                                actorUid: session.effectiveUserId
                            )
                            await reloadMembers()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await store.deleteMember(groupId: group.id, memberUid: m.id)
                                await reloadMembers()
                            }
                        } label: {
                            Text("Удалить")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SolarizedTheme.backgroundColor)
        .refreshable {
            await reloadMembers()
        }
    }

    private var checklistTab: some View {
        List {
            if let error = store.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }

            Section("Добавить") {
                TextField("Новая задача", text: $newChecklistText)
                    .textInputAutocapitalization(.sentences)
                Button("Добавить") {
                    Task {
                        guard let boardId = checklistBoardId else { return }
                        await store.addChecklistItem(
                            groupId: group.id,
                            boardId: boardId,
                            myUid: session.effectiveUserId,
                            text: newChecklistText,
                            assigneeUid: ""
                        )
                        await reloadChecklistItems()
                        await MainActor.run { newChecklistText = "" }
                    }
                }
                .disabled(checklistBoardId == nil || newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Список") {
                ForEach(checklistItems) { it in
                    Button {
                        Task {
                            guard let boardId = checklistBoardId else { return }
                            await store.setChecklistItemDone(
                                groupId: group.id,
                                boardId: boardId,
                                itemId: it.id,
                                myUid: session.effectiveUserId,
                                done: !it.done
                            )
                            await reloadChecklistItems()
                        }
                    } label: {
                        HStack {
                            Image(systemName: it.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(it.done ? .green : .secondary)
                            Text(it.text)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                guard let boardId = checklistBoardId else { return }
                                await store.deleteChecklistItem(groupId: group.id, boardId: boardId, itemId: it.id)
                                await reloadChecklistItems()
                            }
                        } label: {
                            Text("Удалить")
                        }
                    }
                }

                if checklistItems.isEmpty {
                    Text("Пока пусто")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SolarizedTheme.backgroundColor)
        .refreshable {
            await reloadChecklistItems()
        }
    }

    private var pollsTab: some View {
        List {
            if let error = store.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }

            ForEach(polls) { poll in
                PollCardView(groupId: group.id, poll: poll, store: store, myUid: session.effectiveUserId)
            }

            if polls.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Нет голосований")
                        .font(.headline)
                    Text("Создай вопрос и варианты")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SolarizedTheme.backgroundColor)
        .refreshable {
            await reloadPolls()
        }
    }

    private var chatTab: some View {
        VStack(spacing: 0) {
            List {
                if let error = store.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }

                ForEach(messages) { m in
                    ChatMessageRow(
                        title: displayName(for: m.fromUid),
                        isMine: m.fromUid == session.effectiveUserId,
                        text: m.text,
                        subtitle: messageStatusText(m)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .task {
                        if m.fromUid != session.effectiveUserId {
                            await store.markMessageDelivered(groupId: group.id, messageId: m.id, myUid: session.effectiveUserId)
                        }
                    }
                    .onAppear {
                        if m.fromUid != session.effectiveUserId {
                            Task {
                                await store.markMessageSeen(groupId: group.id, messageId: m.id, myUid: session.effectiveUserId)
                            }
                        }
                    }
                }

                if messages.isEmpty {
                    Text("Пока нет сообщений")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SolarizedTheme.backgroundColor)

            Divider()

            HStack(spacing: 10) {
                TextField("Сообщение", text: $newMessageText)
                    .textInputAutocapitalization(.sentences)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 12, shadowRadius: 6, shadowY: 3, padding: nil)

                Button("Отправить") {
                    Task {
                        let t = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        await store.sendMessage(groupId: group.id, myUid: session.effectiveUserId, text: t)
                        await MainActor.run { newMessageText = "" }
                    }
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .task {
            startChatListenerIfNeeded()
        }
    }

    private func reloadAll() async {
        await reloadMembers()

        if checklistBoardId == nil {
            let board = await store.ensureDefaultChecklistBoard(groupId: group.id, myUid: session.effectiveUserId)
            checklistBoardId = board?.id
        }
        await reloadChecklistItems()
        await reloadPolls()
        if selectedTab == .chat {
            startChatListenerIfNeeded()
        }
    }

    private func reloadMembers() async {
        members = await store.loadMembers(groupId: group.id)
        await preloadNamesIfNeeded()
    }

    private func reloadChecklistItems() async {
        guard let boardId = checklistBoardId else {
            checklistItems = []
            return
        }
        checklistItems = await store.loadChecklistItems(groupId: group.id, boardId: boardId)
    }

    private func reloadPolls() async {
        polls = await store.loadPolls(groupId: group.id)
    }

    private func startChatListenerIfNeeded() {
        store.listenMessages(groupId: group.id) { newItems in
            Task { @MainActor in
                messages = newItems
            }
        }
    }

    private func messageStatusText(_ m: GroupMessageDTO) -> String {
        guard m.fromUid == session.effectiveUserId else { return "" }
        let othersCount = max(members.count - 1, 0)
        if othersCount == 0 { return "" }

        let deliveredCount = Set(m.deliveredTo).subtracting([session.effectiveUserId]).count
        let seenCount = Set(m.seenBy).subtracting([session.effectiveUserId]).count

        if seenCount >= othersCount { return "Прочитано"
        }
        if deliveredCount >= othersCount { return "Доставлено"
        }
        return "Отправлено"
    }

    private func displayName(for uid: String) -> String {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = nameCache[trimmed], !n.isEmpty { return n }
        if let f = friendsStore.friends.first(where: { ($0.uid ?? "") == trimmed }) {
            return f.name
        }
        return trimmed
    }

    private func preloadNamesIfNeeded() async {
        let uids = Set(members.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }

        for uid in uids {
            if let existing = nameCache[uid], !existing.isEmpty { continue }

            if let f = friendsStore.friends.first(where: { ($0.uid ?? "") == uid }) {
                nameCache[uid] = f.name
                continue
            }

            let fetched = await store.fetchDisplayName(uid: uid)
            if let fetched, !fetched.isEmpty {
                nameCache[uid] = fetched
            }
        }
    }
}

private struct MemberRow: View {
    let title: String
    let subtitle: String
    let member: GroupMemberDTO
    let onChange: (GroupRole, String) -> Void

    @State private var role: GroupRole
    @State private var subgroup: String

    init(title: String, subtitle: String, member: GroupMemberDTO, onChange: @escaping (GroupRole, String) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.member = member
        self.onChange = onChange
        _role = State(initialValue: member.role)
        _subgroup = State(initialValue: member.subgroup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("Роль", selection: $role) {
                    ForEach(GroupRole.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .pickerStyle(.menu)

                TextField("Подгруппа", text: $subgroup)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                Button("Сохранить") {
                    onChange(role, subgroup)
                }
            }
        }
        .onChange(of: member.role) { _, newValue in
            role = newValue
        }
        .onChange(of: member.subgroup) { _, newValue in
            subgroup = newValue
        }
    }
}

private struct PollCardView: View {
    let groupId: String
    let poll: GroupPollDTO
    @ObservedObject var store: GroupsStore
    let myUid: String

    @State private var votes: [GroupPollVoteDTO] = []
    @State private var isLoadingVotes: Bool = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(poll.question)
                    .font(.headline)

                ForEach(Array(poll.options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        Task {
                            await store.vote(groupId: groupId, pollId: poll.id, myUid: myUid, optionIndex: idx)
                            await reloadVotes()
                        }
                    } label: {
                        HStack {
                            Text(opt)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(countVotes(for: idx))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(poll.isClosed)
                }

                if isLoadingVotes {
                    ProgressView()
                }
            }
            .padding(.vertical, 6)
        }
        .task {
            await reloadVotes()
        }
    }

    private func countVotes(for optionIndex: Int) -> Int {
        votes.filter { $0.optionIndex == optionIndex }.count
    }

    private func reloadVotes() async {
        isLoadingVotes = true
        votes = await store.loadVotes(groupId: groupId, pollId: poll.id)
        isLoadingVotes = false
    }
}

private struct ChatMessageRow: View {
    let title: String
    let isMine: Bool
    let text: String
    let subtitle: String

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(text)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    GroupSandboxDetailView(group: GroupDTO(id: "1", ownerUid: "me", title: "Группа 7", type: .university, createdAt: nil, updatedAt: nil), friendsStore: FriendsStore())
        .environmentObject(UserSessionStore())
}
