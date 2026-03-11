import SwiftUI
import PhotosUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct AccountView: View {
    @EnvironmentObject private var session: UserSessionStore
    @StateObject private var groupsStore = GroupsStore()
    @AppStorage(SolarizedTheme.modeDefaultsKey) private var themeModeRaw = SolarizedTheme.currentMode.rawValue

    @State private var showEditSheet: Bool = false
    @State private var showGroups: Bool = false

    @State private var wikiNotesCount: Int = 0
    @State private var forumPostsCount: Int = 0

    private func profileRowStatic(title: String, subtitle: String, count: String?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let count {
                Text(count)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(SolarizedTheme.surfaceColor.opacity(0.64))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(SolarizedTheme.borderColor, lineWidth: 1)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.70))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.10)
        }
    }

    private var screenBackground: some View {
        LinearGradient(
            colors: [
                SolarizedTheme.backgroundColor,
                SolarizedTheme.accentColor.opacity(0.07),
                SolarizedTheme.backgroundColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenBackground

            Form {
                Section("Профиль") {
                    profileHero
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Сообщество") {
                    Button {
                        Haptics.tap()
                        showGroups = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Группы")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.primary)
                                Text("Участие и подписки")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            Text("\(groupsStore.groups.count)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(SolarizedTheme.surfaceColor.opacity(0.64))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(SolarizedTheme.borderColor, lineWidth: 1)
                                )
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.70))
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.10)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    profileRowStatic(
                        title: "Статьи вики (мои)",
                        subtitle: "Опубликованные и черновики",
                        count: "\(wikiNotesCount)"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    profileRowStatic(
                        title: "Форумы (созданные мной)",
                        subtitle: "Темы и ветки обсуждений",
                        count: "\(forumPostsCount)"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("Оформление") {
                    Picker("Тема", selection: $themeModeRaw) {
                        Text("Светлая").tag(SolarizedTheme.Mode.light.rawValue)
                        Text("Тёмная").tag(SolarizedTheme.Mode.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.tap()
                        session.logout()
                    } label: {
                        Text("Выйти из аккаунта")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditSheet) {
            EditProfileView()
        }
        .navigationDestination(isPresented: $showGroups) {
            GroupsSandboxView(friendsStore: FriendsStore())
        }
        .onAppear {
            Task { await reloadCommunityStats() }
        }
        .onChange(of: session.userId) { _, _ in
            Task { await reloadCommunityStats() }
        }
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let img = session.avatarUIImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.secondary.opacity(0.25))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Пользователь" : session.displayName)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.primary)

                    let email = session.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }

            let study = session.studyPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            let work = session.workPlace.trimmingCharacters(in: .whitespacesAndNewlines)

            if !study.isEmpty {
                infoLine(title: "Учёба", value: study)
            }
            if !work.isEmpty {
                infoLine(title: "Работа", value: work)
            }

            if study.isEmpty || work.isEmpty {
                Text("Добавь место учёбы и работы в профиле")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                Haptics.tap()
                showEditSheet = true
            } label: {
                Text("Редактировать")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(SolarizedTheme.backgroundColor)
                    .background(SolarizedTheme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(SolarizedTheme.secondarySurfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SolarizedTheme.borderColor, lineWidth: 1)
        )
    }

    private func infoLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func metaRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.white.opacity(0.70))
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.55))
            .tracking(0.6)
    }

    private func profileCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 18, x: 0, y: 18)
    }

    private func profileRow(title: String, subtitle: String, count: String?, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let count {
                    Text(count)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.10)
        }
    }

    // MARK: - Helpers

    private func deleteRecipe(_ item: SavedRecipeItem) {
        _ = item
    }

    private func reloadSavedLocal() {
    }

    private func reloadSavedCloud() async {
    }

    private func reloadCommunityStats() async {
        await groupsStore.loadMyGroups(myUid: session.effectiveUserId)

        #if canImport(FirebaseFirestore)
        let uid = session.effectiveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            await MainActor.run {
                wikiNotesCount = 0
                forumPostsCount = 0
            }
            return
        }

        do {
            let notesSnap = try await Firestore.firestore()
                .collection("notes")
                .whereField("createdByUid", isEqualTo: uid)
                .getDocuments()

            let forumSnap = try await Firestore.firestore()
                .collectionGroup("posts")
                .whereField("fromUid", isEqualTo: uid)
                .getDocuments()

            await MainActor.run {
                wikiNotesCount = notesSnap.documents.count
                forumPostsCount = forumSnap.documents.count
            }
        } catch {
            await MainActor.run {
                wikiNotesCount = 0
                forumPostsCount = 0
            }
        }
        #else
        await MainActor.run {
            wikiNotesCount = 0
            forumPostsCount = 0
        }
        #endif
    }
}

private struct CommunityStatChip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 14, shadowRadius: 6, shadowY: 3, padding: nil)
    }
}

// MARK: - Subviews

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SavedRecipeCard: View {
    let item: SavedRecipeItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Удалить", systemImage: "trash")
                    }
                    Button {
                        UIPasteboard.general.string = item.text
                    } label: {
                        Label("Копировать", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }

            Text(item.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: UserSessionStore
    @State private var pickedAvatarItem: PhotosPickerItem?
    
    // Local state for editing
    @State private var displayName: String = ""
    @State private var fullName: String = ""
    @State private var studyPlace: String = ""
    @State private var workPlace: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let img = session.avatarUIImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 100))
                                    .foregroundStyle(.secondary.opacity(0.2))
                            }
                            
                            PhotosPicker(selection: $pickedAvatarItem, matching: .images) {
                                Text("Изменить фото")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Личные данные") {
                    TextField("Отображаемое имя", text: $displayName)
                    TextField("ФИО", text: $fullName)
                    TextField("Место учебы", text: $studyPlace)
                    TextField("Место работы", text: $workPlace)
                }
                
                Section {
                     Button("Сохранить изменения") {
                        save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Load current values
                displayName = session.displayName
                fullName = session.fullName
                studyPlace = session.studyPlace
                workPlace = session.workPlace
            }
            .onChange(of: pickedAvatarItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        let final = normalizeAvatar(uiImage)
                        if let jpg = final.jpegData(compressionQuality: 0.75) {
                            await MainActor.run {
                                session.avatarBase64 = jpg.base64EncodedString()
                            }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        session.displayName = displayName
        session.fullName = fullName
        session.studyPlace = studyPlace
        session.workPlace = workPlace
        session.save()
        #if canImport(FirebaseFirestore)
        session.scheduleProfileSaveToCloud(debounceSeconds: 0.0)
        #endif
    }


    private func normalizeAvatar(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 800
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxSide / size.width, maxSide / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
