import SwiftUI

struct RecipeSettingsView: View {
    @ObservedObject var store: RecipeSettingsStore

    @EnvironmentObject private var session: UserSessionStore

    var body: some View {
        Form {
            Section("Фразы") {
                TextField("Rp.:", text: $store.settings.standardPhrases.recipeStart)
                TextField("M. D. S.", text: $store.settings.standardPhrases.mixAndGive)
                TextField("Sterilisa!", text: $store.settings.standardPhrases.sterilize)
            }

            Section("Правила склонения (окончания)") {
                ForEach($store.settings.grammarRules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("from", text: $rule.suffixFrom)
                            Text("→")
                                .foregroundStyle(.secondary)
                            TextField("to", text: $rule.suffixTo)
                        }
                        TextField("описание", text: $rule.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in
                    store.settings.grammarRules.remove(atOffsets: idx)
                }

                Button("Добавить правило") {
                    store.settings.grammarRules.append(LatinSuffixRule(suffixFrom: "", suffixTo: "", description: ""))
                }
            }

            Section {
                Button("Сбросить настройки") {
                    store.reset()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Настройки рецепта")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.setUserId(session.effectiveUserId)
        }
        .onChange(of: session.userId) { _, _ in
            store.setUserId(session.effectiveUserId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    store.save()
                }
            }
        }
    }
}
