import SwiftUI

struct WikiRecipesView: View {
    let repository: PharmaRepository

    @EnvironmentObject private var session: UserSessionStore
    @StateObject private var vm: WikiViewModel

    @State private var searchText: String = ""

    init(repository: PharmaRepository) {
        self.repository = repository
        _vm = StateObject(wrappedValue: WikiViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                SolarizedTheme.backgroundColor
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Площадка для общения и обсуждений между специалистами. Пользователи могут создавать темы, задавать вопросы, делиться опытом и обсуждать профессиональные вопросы, формируя активное профессиональное сообщество.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Group {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            List {
                                if let error = vm.errorMessage, !error.isEmpty {
                                    Text(error)
                                        .foregroundStyle(.red)
                                }

                                ForEach(vm.items) { item in
                                    NavigationLink {
                                        WikiRecipeDetailView(repository: repository, item: item)
                                            .environmentObject(session)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title.isEmpty ? item.uaVariantId : item.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .lineLimit(2)

                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                if let d = item.updatedAt {
                                                    Text(d, format: .dateTime.day().month().year().hour().minute())
                                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }

                                                let uid = item.updatedByUid.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if !uid.isEmpty {
                                                    Text("by \(String(uid.prefix(8)))")
                                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            let preview = ([
                                                item.formRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                                                item.doseText.trimmingCharacters(in: .whitespacesAndNewlines),
                                                item.quantityN.trimmingCharacters(in: .whitespacesAndNewlines)
                                            ].filter { !$0.isEmpty }).joined(separator: " · ")

                                            if !preview.isEmpty {
                                                Text(preview)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Форум")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: searchText) { _, newValue in
                Task {
                    await vm.load(searchQuery: newValue)
                }
            }
            .task {
                await vm.load(searchQuery: nil)
            }
        }
    }
}
