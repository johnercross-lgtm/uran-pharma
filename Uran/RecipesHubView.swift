import SwiftUI

/// System-first hub for all prescription builders.
/// Keeps both constructors reachable from the same obvious place.
struct RecipesHubView: View {
    let repository: PharmaRepository

    private let emptyCard = DrugCard(
        uaVariantId: "",
        finalRecord: nil,
        uaRegistryVariant: nil,
        enrichedVariant: nil
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                SolarizedTheme.backgroundColor
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Конструкторы для создания медицинских рецептов. Позволяет формировать как готовые, так и экстемпоральные рецепты. Поддерживает работу с ППК, технологией приготовления и другими параметрами, необходимыми для корректного оформления рецептуры.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    List {
                        Section {
                            NavigationLink {
                                RecipeBuilderView(card: emptyCard, repository: repository)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Готовые рецепты")
                                            .font(.headline)
                                        Text("Собрать Rp. (trade/INN, дозировка, signa)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "doc.text")
                                }
                            }

                            NavigationLink {
                                ExtemporaneousFormsView()
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Экстемпоральные")
                                            .font(.headline)
                                        Text("Магистральные формы, расчёты и ППК")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "pills")
                                }
                            }

                            NavigationLink {
                                ExtempEthanolCalculatorView(showsCloseButton: false)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Спирт")
                                            .font(.headline)
                                        Text("Разведение спирта: формула и Фертман")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "drop.fill")
                                }
                            }

                            NavigationLink {
                                ExtempStandardSolutionCatalogView(showsCloseButton: false)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Готовые растворы")
                                            .font(.headline)
                                        Text("Стандартные фармакопейные растворы, Rp. и ППК-превью")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "cross.vial")
                                }
                            }

                            NavigationLink {
                                ExtempStandardSolutionCatalogView(showsCloseButton: false, mode: .special)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Особливі випадки")
                                            .font(.headline)
                                        Text("Люголь та інші нетипові технологічні шаблони")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "staroflife")
                                }
                            }

                            NavigationLink {
                                ExtempBuretteReferenceView(showsCloseButton: false)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Бюретка")
                                            .font(.headline)
                                        Text("Концентрати, розрахунки 500 ml і правила дозування")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "testtube.2")
                                }
                            }
                        } header: {
                            Text("Конструкторы")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Рецепты")
        }
    }
}
