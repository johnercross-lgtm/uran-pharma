import Foundation
import Combine
import SwiftUI

struct LatinSuffixRule: Identifiable, Codable, Hashable {
    var id: UUID
    var suffixFrom: String
    var suffixTo: String
    var description: String

    init(id: UUID = UUID(), suffixFrom: String, suffixTo: String, description: String) {
        self.id = id
        self.suffixFrom = suffixFrom
        self.suffixTo = suffixTo
        self.description = description
    }
}

struct RecipeStandardPhrases: Codable, Hashable {
    var recipeStart: String
    var mixAndGive: String
    var sterilize: String

    static let `default` = RecipeStandardPhrases(
        recipeStart: "Rp.:",
        mixAndGive: "M. D. S.",
        sterilize: "Sterilisa!"
    )
}

struct RecipeSettings: Codable, Hashable {
    var drugNameCase: String
    var quantityPosition: String
    var grammarRules: [LatinSuffixRule]
    var standardPhrases: RecipeStandardPhrases

    static let `default` = RecipeSettings(
        drugNameCase: "Genetivus",
        quantityPosition: "right_align",
        grammarRules: [
            LatinSuffixRule(suffixFrom: "inum", suffixTo: "ini", description: "Второе склонение (-inum -> -ini, Glycerinum -> Glycerini)"),
            LatinSuffixRule(suffixFrom: "ium", suffixTo: "ii", description: "Второе склонение (Natrium -> Natrii)"),
            LatinSuffixRule(suffixFrom: "ole", suffixTo: "oli", description: "Второе склонение (…ole -> …oli)"),
            LatinSuffixRule(suffixFrom: "um", suffixTo: "i", description: "Второе склонение (-um -> -i, Dexamethasonum -> Dexamethasoni)"),
            LatinSuffixRule(suffixFrom: "us", suffixTo: "i", description: "Второе склонение (…us -> …i)"),
            LatinSuffixRule(suffixFrom: "a", suffixTo: "ae", description: "Первое склонение (Silica -> Silicae)"),
            LatinSuffixRule(suffixFrom: "as", suffixTo: "atis", description: "Третье склонение, соли (Sulfas -> Sulfatis)"),
            LatinSuffixRule(suffixFrom: "is", suffixTo: "idis", description: "Третье склонение, соли (Chloris -> Chloridis)"),
            LatinSuffixRule(suffixFrom: "o", suffixTo: "onis", description: "Третье склонение (-o -> -onis)"),
            LatinSuffixRule(suffixFrom: "ine", suffixTo: "ini", description: "INN окончания (Tetracycline -> Tetracyclini)"),
            LatinSuffixRule(suffixFrom: "en", suffixTo: "eni", description: "INN окончания (Ibuprofen -> Ibuprofeni)"),
            LatinSuffixRule(suffixFrom: "ol", suffixTo: "oli", description: "INN окончания (Ambroxol -> Ambroxoli)"),
        ],
        standardPhrases: .default
    )
}

@MainActor
final class RecipeSettingsStore: ObservableObject {
    @Published var settings: RecipeSettings

    private let baseDefaultsKey = "recipe_settings_v1"
    private(set) var userId: String

    init(userId: String = UserSessionStore.defaultUserId) {
        self.userId = userId
        self.settings = .default
        load()
    }

    private var defaultsKey: String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = trimmed.isEmpty ? UserSessionStore.defaultUserId : trimmed
        return "\(baseDefaultsKey)_\(uid)"
    }

    func setUserId(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = trimmed.isEmpty ? UserSessionStore.defaultUserId : trimmed
        if uid == userId { return }
        userId = uid
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(RecipeSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reset() {
        settings = .default
        save()
    }
}
