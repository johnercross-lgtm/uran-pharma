import SwiftUI

struct DrugSearchView: View {
    @StateObject private var viewModel: DrugSearchViewModel

    private let initialQuery: String

    init(initialQuery: String = "") {
        self.initialQuery = initialQuery
        _viewModel = StateObject(wrappedValue: DrugSearchViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                SolarizedTheme.backgroundColor
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("База медицинской информации о препаратах. Здесь можно быстро найти описание лекарства, показания, дозировки, формы выпуска, противопоказания и другую справочную информацию.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    List {
                        if let message = viewModel.errorMessage, !message.isEmpty {
                            Section {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            ForEach(viewModel.results) { item in
                                NavigationLink {
                                    CompendiumDetailView(id: item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(displayTitle(for: item))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)

                                        let inn = (item.inn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !inn.isEmpty {
                                            Text(inn)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        let atc = (item.atcCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !atc.isEmpty {
                                            Text(atc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .opacity(0.8)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                            }
                        }

                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Препараты")
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Название или МНН"
            )
            .onAppear {
                let q = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty, viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.query = q
                }
                Task.detached {
                    try? await CompendiumSQLiteService.shared.openIfNeeded()
                }
            }
        }
    }

    private func displayTitle(for item: CompendiumHit) -> String {
        let brand = (item.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? item.id : brand
    }
}
