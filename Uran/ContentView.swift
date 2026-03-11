//
//  ContentView.swift
//  Uran
//
//  System-minimal UI shell (Light/Dark follows iOS settings)
//

import SwiftUI
import UIKit

enum AssistantNavigationDestination: Hashable {
    case assistant
    case search
    case recipes
    case forum
    case wiki
    case messages
    case groups
    case profile

    var sectionTitle: String {
        switch self {
        case .assistant:
            return "Ассистент"
        case .search:
            return "Search"
        case .recipes:
            return "Recipes"
        case .forum:
            return "Forum"
        case .wiki:
            return "Wiki"
        case .messages:
            return "Messages"
        case .groups:
            return "Groups"
        case .profile:
            return "Профиль"
        }
    }

    var actionTitle: String {
        "Открыть \(sectionTitle)"
    }
}

struct ContentView: View {
    @State private var repository: PharmaRepository?
    @State private var loadError: String?

    @StateObject private var session = UserSessionStore()

    var body: some View {
        Group {
            if session.isLoggedIn {
                if let repository {
                    MainTabView(repository: repository)
                } else if let loadError {
                    NavigationStack {
                        ContentUnavailableView(
                            "База не загрузилась",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadError)
                        )
                        .navigationTitle("URAN")
                    }
                } else {
                    ProgressView("Загрузка базы…")
                }
            } else {
                LoginView()
            }
        }
        .environmentObject(session)
        .tint(.accentColor)
        .task {
            if repository != nil || loadError != nil { return }
            do {
                repository = try PharmaRepository()
            } catch {
                loadError = error.localizedDescription + "\n\nПроверь Target Membership и что файлы БД попадают в Copy Bundle Resources."
            }
        }
        .task(id: repository != nil ? session.userId : "") {
            guard session.isLoggedIn else { return }
            guard let repository else { return }
            let legacy = session.myNotes
            if repository.migrateLegacyMyNotesIfNeeded(legacyText: legacy, updatedByUid: session.effectiveUserId) {
                await MainActor.run {
                    session.myNotes = ""
                    session.save()
#if canImport(FirebaseFirestore)
                    session.scheduleProfileSaveToCloud()
#endif
                }
            }
        }
        .task(id: session.userId) {
            guard session.isLoggedIn else { return }
            guard let repository else { return }
            await repository.syncUserRecipeAnnotationsFromCloud(userId: session.effectiveUserId)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// System-first navigation.
/// - Minimal cognitive load: 6 obvious destinations
/// - Light/Dark follows iOS settings automatically
private struct MainTabView: View {
    private enum MainTab: Hashable {
        case assistant
        case search
        case recipes
        case forum
        case wiki
        case messages
        case groups
        case profile

        init(destination: AssistantNavigationDestination) {
            switch destination {
            case .assistant:
                self = .assistant
            case .search:
                self = .search
            case .recipes:
                self = .recipes
            case .forum:
                self = .forum
            case .wiki:
                self = .wiki
            case .messages:
                self = .messages
            case .groups:
                self = .groups
            case .profile:
                self = .profile
            }
        }
    }

    let repository: PharmaRepository
    @StateObject private var friendsStore = FriendsStore()
    @State private var selectedTab: MainTab = .assistant

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ReferenceAssistantView(onOpenDestination: openDestinationFromAssistant)
            }
            .tabItem { Label("Ассистент", systemImage: "text.book.closed") }
            .tag(MainTab.assistant)

            DrugSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(MainTab.search)

            RecipesHubView(repository: repository)
                .tabItem { Label("Recipes", systemImage: "pencil.and.list.clipboard") }
                .tag(MainTab.recipes)

            WikiRecipesView(repository: repository)
                .tabItem { Label("Forum", systemImage: "text.bubble") }
                .tag(MainTab.forum)

            WikiNotesFeedView(repository: repository)
                .tabItem { Label("Wiki", systemImage: "book") }
                .tag(MainTab.wiki)

            NavigationStack {
                DirectChatsListView()
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            .tag(MainTab.messages)

            GroupsSandboxView(friendsStore: friendsStore)
                .tabItem { Label("Groups", systemImage: "person.3") }
                .tag(MainTab.groups)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
            .tag(MainTab.profile)
        }
    }

    private func openDestinationFromAssistant(_ destination: AssistantNavigationDestination) {
        selectedTab = MainTab(destination: destination)
    }
}

#Preview {
    ContentView()
}
