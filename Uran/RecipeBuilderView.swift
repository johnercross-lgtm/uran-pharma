import SwiftUI
import UIKit

struct RecipeBuilderView: View {
    private let repository: PharmaRepository?

    @State private var card: DrugCard

    @EnvironmentObject private var session: UserSessionStore

    @StateObject private var settingsStore = RecipeSettingsStore()

    @State private var brandName: String = ""
    @State private var innName: String = ""
    @State private var dosage: String = ""
    @State private var quantityN: String = ""
    @State private var volume: String = ""
    @State private var form: RecipeForm = .tab
    @State private var routeOfAdministration: String = ""
    @State private var packagingForm: String = ""
    @State private var formContext: String = ""
    @State private var signa: String = ""
    @State private var outputFormat: RecipeOutputFormat = .short

    @State private var useTradeName: Bool = false

    @State private var drugQuery: String = ""
    @State private var drugResults: [DrugSearchResult] = []
    @State private var drugSearchError: String?
    @State private var isDrugSearchLoading: Bool = false
    @State private var isSelectingDrug: Bool = false
    @State private var pendingSearchWorkItem: DispatchWorkItem?

    @State private var pendingAutoSaveWorkItem: DispatchWorkItem?
    @State private var lastAutoSavedFingerprint: String = ""

    @State private var showSettings: Bool = false
    @State private var showSelectedDrugCard: Bool = false
    @State private var showInstruction: Bool = false
    @State private var showRxHelp: Bool = false

    @State private var showAdvancedFields: Bool = false

    @State private var hasSavedAnnotations: Bool = false

    @State private var parsedPreview: RecipeParsing.ParsedDosageFormText?
    @State private var parsedPreviewError: String?

    @State private var parsedPreviewVariants: [RecipeParsing.ParsedDosageFormText] = []
    @State private var parsedPreviewSelectedIndex: Int = 0

    @State private var sharedDoseText: String = ""
    @State private var sharedQuantityN: String = ""
    @State private var sharedFormRaw: String = ""
    @State private var sharedSignaText: String = ""
    @State private var hasSharedRecipe: Bool = false

    @State private var showSavedAlert: Bool = false
    @StateObject private var keyboardObserver = KeyboardObserver()
    @State private var activeQuickInputField: QuickInputField?

    private enum QuickInputField: Hashable {
        case dosage
        case quantity
        case volume
        case signa

        var title: String {
            switch self {
            case .dosage:
                return "Доза / концентрация"
            case .quantity:
                return "Количество"
            case .volume:
                return "Объём"
            case .signa:
                return "Signa"
            }
        }

        var placeholder: String {
            switch self {
            case .dosage:
                return "Например 0,5 mg или 2,5%"
            case .quantity:
                return "Например N 20"
            case .volume:
                return "Например 10 ml"
            case .signa:
                return "Инструкция для пациента"
            }
        }

        var keyboardType: UIKeyboardType {
            switch self {
            case .signa:
                return .default
            case .quantity:
                return .numbersAndPunctuation
            case .dosage, .volume:
                return .decimalPad
            }
        }

        var tokens: [QuickInputToken] {
            switch self {
            case .dosage:
                return [
                    QuickInputToken(label: "0,25", insertion: "0,25"),
                    QuickInputToken(label: "0,5", insertion: "0,5"),
                    QuickInputToken(label: "1", insertion: "1"),
                    QuickInputToken(label: "mg", insertion: "mg"),
                    QuickInputToken(label: "g", insertion: "g"),
                    QuickInputToken(label: "%", insertion: "%"),
                    QuickInputToken(label: "ml", insertion: "ml")
                ]
            case .quantity:
                return [
                    QuickInputToken(label: "N", insertion: "N"),
                    QuickInputToken(label: "5", insertion: "5"),
                    QuickInputToken(label: "10", insertion: "10"),
                    QuickInputToken(label: "20", insertion: "20"),
                    QuickInputToken(label: "30", insertion: "30")
                ]
            case .volume:
                return [
                    QuickInputToken(label: "5", insertion: "5"),
                    QuickInputToken(label: "10", insertion: "10"),
                    QuickInputToken(label: "20", insertion: "20"),
                    QuickInputToken(label: "30", insertion: "30"),
                    QuickInputToken(label: "ml", insertion: "ml")
                ]
            case .signa:
                return [
                    QuickInputToken(label: "По 1", insertion: "По 1"),
                    QuickInputToken(label: "2 р/д", insertion: "2 раза в день"),
                    QuickInputToken(label: "3 р/д", insertion: "3 раза в день"),
                    QuickInputToken(label: "после еды", insertion: "после еды"),
                    QuickInputToken(label: "наружно", insertion: "наружно"),
                    QuickInputToken(label: "в глаза", insertion: "в глаза"),
                    QuickInputToken(label: "intra nasum", insertion: "intra nasum")
                ]
            }
        }
    }

    private var userToolbarHeader: some View {
        let trimmedName = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = session.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? (trimmedEmail.isEmpty ? "Без имени" : trimmedEmail) : trimmedName

        return HStack(alignment: .center, spacing: 10) {
            if let img = session.avatarUIImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary.opacity(0.25))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if !trimmedName.isEmpty, !trimmedEmail.isEmpty {
                    Text(trimmedEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var hasSelectedDrug: Bool {
        !card.uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applySharedRecipe() {
        Haptics.tap()
        if !sharedDoseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dosage = sharedDoseText
        }
        if !sharedQuantityN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quantityN = sharedQuantityN
        }
        if !sharedFormRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form = RecipeParsing.inferForm(from: sharedFormRaw)
        }
        if !sharedSignaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            signa = sharedSignaText
        }
    }

    private func loadSharedRecipeIfPossible(uaVariantId: String) async {
#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let repository else { return }
        let trimmed = uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let data = await repository.loadSharedRecipeFromCloud(uaVariantId: trimmed)
        await MainActor.run {
            let doseText = (data?["dose_text"] as? String) ?? ""
            let quantity = (data?["quantity_n"] as? String) ?? ""
            let formRaw = (data?["form_raw"] as? String) ?? ""
            let signaText = (data?["signa_text"] as? String) ?? ""

            sharedDoseText = doseText
            sharedQuantityN = quantity
            sharedFormRaw = formRaw
            sharedSignaText = signaText
            hasSharedRecipe = !doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !formRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
#else
        _ = uaVariantId
#endif
    }

    private var rxHelpText: String {
        """
        Логика выписки рецепта строится на указании формы, названия действующего вещества в родительном падеже, его концентрации или дозировки.

        1. Твердые формы (Таблетки)
        Указывается доза в одной таблетке и их общее количество.
        Логика: Rp.: Tab. [Название] [Доза], затем D. t. d. N [Количество].
        Пример: Rp.: Tab. Atenololi 0,05 (Возьми таблетки атенолола по 0,05 г).
        Выдача: D. t. d. N 30 (Выдай таких доз числом 30).

        2. Ампулы (Растворы для инъекций)
        Прописывается объем одной ампулы и концентрация вещества.
        Логика: Rp.: Sol. [Название] [Концентрация] - [Объем].
        Пример: Rp.: Sol. Suprastini 2% - 1 ml.
        Выдача: D. t. d. N 5 in amp. (Выдай 5 таких доз в ампулах).

        3. Мягкие формы (Мази, Гели, Суппозитории)
        Для мазей и гелей указывается общий вес упаковки. Суппозитории выписываются поштучно.
        Мазь/Гель: Rp.: Ung. (или Gel.) [Название] [Вес]. Пример: Rp.: Ung. Tetracyclini 1% - 5,0.
        Суппозитории: Rp.: Supp. [Название] [Доза]. Пример: Rp.: Supp. \"Anuzolum\" N 10 (Выдай свечи «Анузол» числом 10).

        4. Спреи и Аэрозоли
        Спреи для носа (nasal) и горла часто выписывают по торговому названию или количеству доз.
        Спрей назальный: Rp.: Spr. Mometasoni 0,05 - 120 doses. Применяется по дозам в каждый носовой ход.
        Спрей для горла: Часто выписывается как Spr. [Торговое название] [Объем]. Пример: Rp.: Spr. \"Hexoral\" 40 ml.

        5. Растворы (Наружные и для ингаляций)
        Наружные: Выписываются общим объемом. Пример: Rp.: Sol. Nitrofungini 1% - 25 ml.
        Для ингаляций (через небулайзер): Указывается концентрация и объем.

        6. Капли (Глазные, Ушные, Оральные)
        Капли всегда начинаются со слова Guttas (если выписываются как форма) или Solutio (как раствор).
        Глазные: Обычно 5–10 мл. Rp.: Sol. Levomycetini 0,25% - 10 ml.
        Ушные: Rp.: Sol. \"Otipax\" 16 ml.
        Оральные (внутрь): Выписываются как «капли для приема внутрь». Пример: Rp.: Guttas \"Valocordin\" 20 ml.

        Пояснение к Signa (S.):
        Это инструкция для пациента. Она всегда начинается с большой буквы и описывает: сколько, куда и как часто (например: «По 1 таб. 3 раза в день после еды»).
        """
    }

    private func rxBadgeKind(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return "" }

        let hasOtc = s.contains("otc") || s.contains("без рецеп") || s.contains("безрецеп")
        let hasRx = s.contains("rx") || s.contains("за рецеп") || s.contains("рецепт")

        if hasOtc && hasRx { return "both" }
        if hasRx { return "rx" }
        if hasOtc { return "otc" }
        return ""
    }

    private func mergedData(card: DrugCard) -> [String: String] {
        var out: [String: String] = [:]
        let sources: [[String: String?]?] = [card.finalRecord, card.uaRegistryVariant, card.enrichedVariant]
        for dict in sources {
            guard let dict else { continue }
            for (k, v) in dict {
                if out[k] != nil { continue }
                guard let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                out[k] = v
            }
        }
        return out
    }

    private func isHiddenKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if k.contains("source") { return true }
        if k.contains("provider") { return true }
        if k.contains("method") { return true }
        if k.contains("embedding") { return true }
        if k.contains("rank") { return true }
        return false
    }

    private func normalizeSelection(_ selection: String, target: AnnotationTarget) -> String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        switch target {
        case .dose:
            let extracted = RecipeParsing.extractDose(from: trimmed)
            return extracted.isEmpty ? trimmed : extracted
        case .concentration:
            let extracted = RecipeParsing.extractConcentration(from: trimmed)
            return extracted.isEmpty ? trimmed : extracted
        case .quantity:
            let n = RecipeParsing.extractQuantityN(from: trimmed)
            if !n.isEmpty { return n }
            let digits = trimmed.filter { $0.isNumber }
            return digits.isEmpty ? trimmed : digits
        case .form:
            return trimmed
        case .signa:
            return trimmed
        }
    }

    private var emptyCard: DrugCard {
        DrugCard(
            uaVariantId: "",
            finalRecord: nil,
            uaRegistryVariant: nil,
            enrichedVariant: nil
        )
    }

    init(card: DrugCard, repository: PharmaRepository? = nil) {
        self.repository = repository
        _card = State(initialValue: card)
    }

    private var prescription: Prescription {
        return RecipeGenerator.makePrescription(
            draft: recipeDraft(),
            settings: settingsStore.settings,
            drugId: card.uaVariantId
        )
    }

    private var outputText: String {
        let draft = recipeDraft(useTradeName: outputFormat == .brand ? true : nil)
        let base: String
        switch outputFormat {
        case .short:
            base = RecipeGenerator.generateShortText(prescription: prescription)
        case .expanded:
            base = RecipeGenerator.generateExpandedText(prescription: prescription)
        case .brand:
            base = RecipeGenerator.generateBrandText(
                draft: draft,
                settings: settingsStore.settings
            )
        case .json:
            base = RecipeGenerator.encodeJSON(prescription: prescription)
        }

        if outputFormat == .json {
            return base
        }
        let withContext = applyFormContext(to: base, draft: draft)
        return applyRouteAndPackaging(to: withContext)
    }

    private func recipeDraft(useTradeName forcedTradeName: Bool? = nil) -> RecipeDraft {
        var draft = RecipeDraft(
            innName: innName,
            brandName: brandName,
            form: form,
            dosage: dosage,
            quantityN: quantityN,
            volume: volume,
            signa: signa,
            useTradeName: forcedTradeName ?? useTradeName
        )

        let context = formContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if context == "Ophthalmic" {
            let lowerSigna = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !lowerSigna.contains("в глаза") {
                if draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.signa = "в глаза"
                } else {
                    draft.signa = (draft.signa.trimmingCharacters(in: .whitespacesAndNewlines) + " в глаза")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            if draft.form == .sol, draft.quantityN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.quantityN = "10 ml"
            }
        } else if context == "Nasal" {
            if draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.signa = "intra nasum"
            }
        } else if context == "Dermatologic" {
            let lowerSigna = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !lowerSigna.contains("наруж") {
                if draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.signa = "наружно"
                } else {
                    draft.signa = (draft.signa.trimmingCharacters(in: .whitespacesAndNewlines) + " наружно")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return draft
    }

    private let contextOptions: [String] = [
        "Ophthalmic",
        "Nasal",
        "Dermatologic"
    ]

    private var routeOptions: [String] {
        [
            "per os",
            "sub linguam",
            "trans buccam",
            "per rectum",
            "in oculos",
            "intra nasum",
            "per inhalationem",
            "transdermaliter",
            "intra musculum (i/m)",
            "intra venam (i/v)",
            "sub cutem (s/c)"
        ]
    }

    private var packagingOptions: [String] {
        [
            "in amp.",
            "in flac.",
            "in tub.",
            "in caps.",
            "in dragee",
            "in supp.",
            "in tab.",
            "in vitro nigro",
            "ex tempore"
        ]
    }

    private func applyFormContext(to text: String, draft: RecipeDraft) -> String {
        let ctx = formContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if ctx.isEmpty { return text }

        if ctx == "Ophthalmic" {
            return applyOphthalmicContext(to: text, form: draft.form)
        }

        return text
    }

    private func applyOphthalmicGuttasBrandContext(to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }

        let brand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted: String = {
            if brand.isEmpty { return "" }
            if brand.contains("\"") { return brand }
            if brand.contains("«") || brand.contains("»") { return brand }
            return "\"\(brand)\""
        }()

        let volume = quantityN.trimmingCharacters(in: .whitespacesAndNewlines)
        var rp = "Rp.: Guttas ophthalmicas"
        if !quoted.isEmpty {
            rp += " \(quoted)"
        }
        if !volume.isEmpty {
            rp += " \(volume)"
        }
        lines[0] = rp.trimmingCharacters(in: .whitespaces)
        return lines.joined(separator: "\n")
    }

    private func drugResultTitle(_ item: DrugSearchResult) -> String {
        let b = item.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? item.uaVariantId : b
    }

    private func drugResultInn(_ item: DrugSearchResult) -> String {
        item.innName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func drugResultFormDoseLine(_ item: DrugSearchResult) -> String {
        item.formDoseLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func drugResultRegLine(_ item: DrugSearchResult) -> String {
        let reg = item.registry.trimmingCharacters(in: .whitespacesAndNewlines)
        let dc = item.dispensingConditions.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([!reg.isEmpty ? reg : nil, !dc.isEmpty ? dc : nil].compactMap { $0 }).joined(separator: " · ")
    }

    private func drugResultRxKind(_ item: DrugSearchResult) -> String {
        rxBadgeKind(item.rxStatus)
    }



    @ViewBuilder
    private func drugResultBadges(_ item: DrugSearchResult) -> some View {
        if item.isAnnotated {
            Text("Сохранено")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(Capsule())
        }

        let kind = rxBadgeKind(item.rxStatus)
        if kind == "rx" {
            Text("Rx")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12))
                .clipShape(Capsule())
        } else if kind == "otc" {
            Text("OTC")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        } else if kind == "both" {
            Text("Rx/OTC")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private func applyOphthalmicContext(to text: String, form: RecipeForm) -> String {
        let lowerForm = form.rawValue.lowercased()
        if !lowerForm.contains("ung") { return text }

        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        guard lines[0].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Rp.: ") else { return text }

        if lines[0].lowercased().contains("ophthalmic") {
            return text
        }

        let prefix = "Ung."
        let marker = "Rp.: \(prefix) "
        if !lines[0].hasPrefix(marker) {
            return text
        }

        if lines[0].lowercased().hasPrefix("rp.: \(prefix.lowercased()) ophthalmici ") {
            return text
        }

        lines[0] = lines[0].replacingOccurrences(of: marker, with: "Rp.: \(prefix) ophthalmici ")
        return lines.joined(separator: "\n")
    }

    private func applyRouteAndPackaging(to text: String) -> String {
        let pack = packagingForm.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = routeOfAdministration.trimmingCharacters(in: .whitespacesAndNewlines)

        if pack.isEmpty, route.isEmpty { return text }

        var lines = text.components(separatedBy: "\n")
        if lines.isEmpty { return text }

        if !pack.isEmpty {
            for i in lines.indices {
                let lower = lines[i].trimmingCharacters(in: .whitespaces).lowercased()
                if lower.hasPrefix("d.t.d") || lower.hasPrefix("d. t. d") || lower.hasPrefix("da tales") {
                    if !lines[i].lowercased().contains(pack.lowercased()) {
                        lines[i] = (lines[i] + " " + pack).trimmingCharacters(in: .whitespaces)
                    }
                    break
                }
            }
        }

        if !route.isEmpty {
            for i in lines.indices {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("S.") || trimmed.hasPrefix("S.:") || trimmed.hasPrefix("D. S") || trimmed.hasPrefix("D. S.") {
                    if !lines[i].contains(route) {
                        if trimmed == "S." || trimmed == "S.:" {
                            lines[i] = "S. \(route)"
                        } else {
                            lines[i] = (lines[i] + " " + route).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    break
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private var dosageWarning: String? {
        let trimmed = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let lower = trimmed.lowercased()
        let hasUnit = lower.contains("mg") || lower.contains("мг")
            || lower.contains("g") || lower.contains("г")
            || lower.contains("ml") || lower.contains("мл")
            || lower.contains("%")
            || lower.contains("me") || lower.contains("ме")
            || lower.contains("iu") || lower.contains("ед")
        if hasUnit { return nil }

        let digitsOnly = trimmed.filter { $0.isNumber || $0 == "," || $0 == "." }
        if digitsOnly.isEmpty { return nil }
        let normalized = digitsOnly.replacingOccurrences(of: ",", with: ".")
        guard let val = Double(normalized) else { return nil }
        if val >= 10 {
            return "Похоже, в дозе нет единиц измерения (mg/ml/%) — проверь поле \"Доза/конц.\""
        }
        return nil
    }

    var body: some View {
        AnyView(
            rootView
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Рецепт")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: dosage) { _, _ in scheduleAutoSave() }
                .onChange(of: quantityN) { _, _ in scheduleAutoSave() }
                .onChange(of: volume) { _, _ in scheduleAutoSave() }
                .onChange(of: form) { _, _ in scheduleAutoSave() }
                .onChange(of: signa) { _, _ in scheduleAutoSave() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        userToolbarHeader
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.tap()
                            showRxHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Настройки") {
                            Haptics.tap()
                            showSettings = true
                        }
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Готово") {
                            Haptics.tap()
                            hideKeyboard()
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        RecipeSettingsView(store: settingsStore)
                    }
                }
                .sheet(isPresented: $showRxHelp) {
                    NavigationStack {
                        ScrollView {
                            AnnotatableTextView(text: rxHelpText, font: .systemFont(ofSize: 14), foregroundColor: .label) { target, selection in
                                let normalized = normalizeSelection(selection, target: target)
                                guard !normalized.isEmpty else { return }

                                switch target {
                                case .dose:
                                    dosage = normalized
                                case .concentration:
                                    dosage = normalized
                                case .quantity:
                                    quantityN = normalized
                                case .form:
                                    form = RecipeParsing.inferForm(from: normalized)
                                case .signa:
                                    signa = normalized
                                }

                                if hasSelectedDrug, let repository {
                                    let uaVariantId = card.uaVariantId
                                    Task {
                                        do {
                                            switch target {
                                            case .dose:
                                                try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, doseText: normalized)
                                            case .concentration:
                                                try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, doseText: normalized)
                                            case .quantity:
                                                try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, quantityN: normalized)
                                            case .form:
                                                try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, formRaw: normalized)
                                            case .signa:
                                                try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, signaText: normalized)
                                            }
                                        } catch {
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }
                        .navigationTitle("Инструкция")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Готово") {
                                    Haptics.tap()
                                    showRxHelp = false
                                }
                            }
                        }
                    }
                }
                .navigationDestination(isPresented: $showInstruction) {
                    if let repository {
                        DrugDetailView(repository: repository, uaVariantId: card.uaVariantId) { target, value in
                            switch target {
                            case .dose:
                                dosage = value
                            case .concentration:
                                dosage = value
                            case .quantity:
                                quantityN = value
                            case .form:
                                form = RecipeParsing.inferForm(from: value)
                            case .signa:
                                signa = value
                            }
                        }
                    }
                }
                .overlay {
                    if showSelectedDrugCard {
                        selectedDrugOverlay
                    }
                }
                .overlay(alignment: .bottom) {
                    quickInputOverlay
                }
                .onAppear {
                    settingsStore.setUserId(session.effectiveUserId)
                    prefill()
                }
                .onChange(of: session.userId) { _, _ in
                    settingsStore.setUserId(session.effectiveUserId)
                    prefill(overwrite: true)
                }
        )
    }

    private var rootView: some View {
        ZStack(alignment: .topLeading) {
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

            Form {
                drugSection
                recognizedSection
                dataSection
                recipeSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(SolarizedTheme.backgroundColor)
    }

    @ViewBuilder
    private var drugSection: some View {
        if repository != nil {
            Section("Препарат") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Поиск препарата", text: $drugQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(SolarizedTheme.surfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                        )
                        .onChange(of: drugQuery) { _, newValue in
                            scheduleSearch(newValue)
                        }

                    Button("Сбросить") {
                        Haptics.tap()
                        reset()
                    }
                    .foregroundStyle(.red)
                }
                .padding(12)
                .background(SolarizedTheme.secondarySurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let drugSearchError {
                    Text(drugSearchError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isDrugSearchLoading || isSelectingDrug {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if !drugResults.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(drugResults.prefix(20)) { item in
                                DrugResultRow(
                                    title: drugResultTitle(item),
                                    inn: drugResultInn(item),
                                    formDoseLine: drugResultFormDoseLine(item),
                                    regLine: drugResultRegLine(item),
                                    isAnnotated: item.isAnnotated,
                                    rxKind: drugResultRxKind(item),
                                    onTap: {
                                        Haptics.tap()
                                        selectDrug(item)
                                    }
                                )

                                if item.id != drugResults.prefix(20).last?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxHeight: 260)
                    .background(SolarizedTheme.secondarySurfaceColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var recognizedSection: some View {
        if hasSelectedDrug {
            Section("Распознано") {
                if let preview = parsedPreview {
                    if parsedPreviewVariants.count >= 2 {
                        Picker("Вариант", selection: $parsedPreviewSelectedIndex) {
                            ForEach(parsedPreviewVariants.indices, id: \.self) { idx in
                                let v = parsedPreviewVariants[idx]
                                let title = v.formNorm.isEmpty ? v.form.rawValue : v.formNorm
                                Text("\(idx + 1): \(title)").tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: parsedPreviewSelectedIndex) { _, newValue in
                            let idx = max(0, min(newValue, parsedPreviewVariants.count - 1))
                            parsedPreviewSelectedIndex = idx
                            self.parsedPreview = parsedPreviewVariants[idx]

                            if hasSelectedDrug, let repository {
                                let uaVariantId = card.uaVariantId
                                let json = RecipeParsing.encodeParsedDosageBundle(variants: parsedPreviewVariants, selectedIndex: idx)
                                if !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Task {
                                        try? await repository.saveParsedDosageCache(uaVariantId: uaVariantId, parsedJson: json)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Форма")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(preview.formNorm.isEmpty ? preview.form.rawValue : preview.formNorm)
                            .font(.callout.weight(.semibold))
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Сила")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if preview.isComplexStrength {
                            Text("complex")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.red)
                        } else {
                            Text(preview.strengthText.isEmpty ? "—" : preview.strengthText)
                                .font(.callout.weight(.semibold))
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Упаковка")
                            .foregroundStyle(.secondary)
                        Spacer()
                        let mlText: String? = {
                            guard let ml = preview.packVolumeMl else { return nil }
                            let s = String(format: "%.2f", ml)
                                .replacingOccurrences(of: ".", with: ",")
                                .replacingOccurrences(of: ",00", with: "")
                            return "\(s) ml"
                        }()
                        let parts = [
                            preview.packCount != nil ? "N \(preview.packCount!)" : nil,
                            mlText,
                            preview.container.isEmpty ? nil : preview.container
                        ].compactMap { $0 }
                        Text(parts.isEmpty ? "—" : parts.joined(separator: " · "))
                            .font(.callout.weight(.semibold))
                    }

                    if preview.isComplexStrength {
                        Text("Состав/дозировка выглядят как комбинация — авто-нормализация отключена, лучше проверить вручную")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let parsedPreviewError {
                        Text(parsedPreviewError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Применить распознанное") {
                        Haptics.tap()
                        dosage = preview.dosageSuggestion
                        quantityN = preview.quantityNSuggestion
                        volume = preview.volumeSuggestion
                        form = preview.form
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("Нет данных")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectedDrugOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showSelectedDrugCard = false
                }

            VStack(spacing: 10) {
                HStack {
                    Text("Карточка")
                        .font(.headline)
                    Spacer()

                    if repository != nil {
                        Button {
                            showSelectedDrugCard = false
                            DispatchQueue.main.async {
                                showInstruction = true
                            }
                        } label: {
                            Image(systemName: "book")
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showSelectedDrugCard = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }

                let manufacturer = (card.uaRegistryVariant?["manufacturer"] ?? nil) ?? ""
                let formText = (card.uaRegistryVariant?["form"] ?? nil) ?? ""
                let composition = (card.uaRegistryVariant?["composition"] ?? nil) ?? ""

                let merged = mergedData(card: card)
                let keys = merged.keys
                    .filter { !isHiddenKey($0) }
                    .sorted()

                VStack(alignment: .leading, spacing: 6) {
                    Text(brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : brandName)
                        .font(.title2.weight(.semibold))

                    if !innName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(innName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if !manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(manufacturer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0.7)
                    }

                    Text(card.uaVariantId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(keys, id: \.self) { key in
                            if let value = merged[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(key)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    AnnotatableTextView(text: value, font: .systemFont(ofSize: 14), foregroundColor: .label) { target, selection in
                                        let normalized = normalizeSelection(selection, target: target)
                                        guard !normalized.isEmpty else { return }

                                        switch target {
                                        case .dose:
                                            dosage = normalized
                                        case .concentration:
                                            dosage = normalized
                                        case .quantity:
                                            quantityN = normalized
                                        case .form:
                                            form = RecipeParsing.inferForm(from: normalized)
                                        case .signa:
                                            signa = normalized
                                        }

                                        if let repository {
                                            Task {
                                                do {
                                                    switch target {
                                                    case .dose:
                                                        try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, doseText: normalized)
                                                    case .concentration:
                                                        try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, doseText: normalized)
                                                    case .quantity:
                                                        try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, quantityN: normalized)
                                                    case .form:
                                                        try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, formRaw: normalized)
                                                    case .signa:
                                                        try await repository.saveUserRecipeAnnotation(uaVariantId: card.uaVariantId, signaText: normalized)
                                                    }
                                                } catch {
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !formText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dosage Form")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(formText)
                                    .font(.body)
                                    .onTapGesture {
                                        form = RecipeParsing.inferForm(from: formText)
                                    }
                            }
                        }

                        if !composition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Состав")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(composition)
                                    .font(.body)
                                    .onTapGesture {
                                        let d = RecipeParsing.extractDose(from: composition)
                                        if !d.isEmpty { dosage = d }
                                        let q = RecipeParsing.extractQuantityN(from: composition)
                                        if !q.isEmpty { quantityN = q }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
            .padding(14)
            .frame(maxWidth: 520)
            .background(SolarizedTheme.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
            )
            .padding(16)
        }
    }

    private func fieldShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(SolarizedTheme.surfaceColor.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
            )
    }

    private func stepCard<Content: View>(
        _ title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(12)
        .background(SolarizedTheme.surfaceColor.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SolarizedTheme.borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dataStatusRow: some View {
        if hasSelectedDrug {
            HStack(spacing: 8) {
                if hasSavedAnnotations {
                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SolarizedTheme.surfaceColor.opacity(0.8))
                        .clipShape(Capsule())
                }

                if hasSharedRecipe {
                    Button("Применить общие") {
                        applySharedRecipe()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                }

                Spacer()

                Button("Сохранить") {
                    saveSelectedDrugAnnotation()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
        } else {
            Text("Выберите препарат выше, чтобы автоматически подставить часть полей.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSection: some View {
        Section("Конструктор") {
            VStack(alignment: .leading, spacing: 14) {
                dataStatusRow

                stepCard(
                    "1. Основа рецепта",
                    note: "Сначала задайте наименование и форму, потом режим вывода."
                ) {
                    HStack(spacing: 10) {
                        fieldShell {
                            TextField("Бренд (если нужен)", text: $brandName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.plain)
                        }

                        if hasSelectedDrug {
                            Button {
                                Haptics.tap()
                                hideKeyboard()
                                showSelectedDrugCard = true
                            } label: {
                                Image(systemName: "book")
                                    .foregroundStyle(SolarizedTheme.accentColor)
                                    .padding(10)
                                    .background(SolarizedTheme.surfaceColor.opacity(0.94))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    fieldShell {
                        HStack {
                            Text(useTradeName ? "Формат: торговое название" : "Формат: МНН")
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: $useTradeName)
                                .labelsHidden()
                                .tint(SolarizedTheme.accentColor)
                        }
                    }

                    fieldShell {
                        TextField("МНН / название вещества", text: $innName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }

                    fieldShell {
                        HStack {
                            Text("Лекарственная форма")
                                .foregroundStyle(.primary)
                            Spacer()
                            Picker("Форма", selection: $form) {
                                ForEach(RecipeForm.allCases) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(SolarizedTheme.accentColor)
                        }
                    }
                }

                stepCard(
                    "2. Доза и объём",
                    note: "Укажите дозировку, количество и общий объём упаковки."
                ) {
                    fieldShell {
                        TextField("Доза/конц. (например 0,5 или 2,5%)", text: $dosage, onEditingChanged: { editing in
                            if editing {
                                activateQuickInput(.dosage)
                            }
                        })
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }

                    fieldShell {
                        TextField("N количество препарата", text: $quantityN, onEditingChanged: { editing in
                            if editing {
                                activateQuickInput(.quantity)
                            }
                        })
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }

                    fieldShell {
                        TextField("Объём (например 10 ml)", text: $volume, onEditingChanged: { editing in
                            if editing {
                                activateQuickInput(.volume)
                            }
                        })
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                    }

                    if let dosageWarning {
                        Text(dosageWarning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                stepCard(
                    "3. Signa для пациента",
                    note: "Опишите как принимать: сколько, как часто и при каких условиях."
                ) {
                    AnnotatableTextEditor(text: $signa, font: .systemFont(ofSize: 15), foregroundColor: .label) { target, selection in
                        let normalized = normalizeSelection(selection, target: target)
                        guard !normalized.isEmpty else { return }

                        switch target {
                        case .dose:
                            dosage = normalized
                        case .concentration:
                            dosage = normalized
                        case .quantity:
                            quantityN = normalized
                        case .form:
                            form = RecipeParsing.inferForm(from: normalized)
                        case .signa:
                            signa = normalized
                        }

                        if hasSelectedDrug, let repository {
                            let uaVariantId = card.uaVariantId
                            Task {
                                do {
                                    switch target {
                                    case .dose:
                                        try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, doseText: normalized)
                                    case .concentration:
                                        try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, doseText: normalized)
                                    case .quantity:
                                        try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, quantityN: normalized)
                                    case .form:
                                        try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, formRaw: normalized)
                                    case .signa:
                                        try await repository.saveUserRecipeAnnotation(uaVariantId: uaVariantId, signaText: normalized)
                                    }
                                } catch {
                                }
                            }
                        }
                    }
                    .frame(minHeight: 110)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            activateQuickInput(.signa)
                        }
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(SolarizedTheme.surfaceColor.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                    )

                    if signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Подсказка: «По 1 таб. 2 раза в день после еды»")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $showAdvancedFields) {
                    stepCard(
                        "Дополнительные параметры",
                        note: "Опционально: контекст формы, путь введения и форма выдачи."
                    ) {
                        fieldShell {
                            HStack {
                                Text("Контекст")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("Контекст", selection: $formContext) {
                                    Text("Авто").tag("")
                                    ForEach(contextOptions, id: \.self) { v in
                                        Text(v).tag(v)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(SolarizedTheme.accentColor)
                            }
                        }

                        fieldShell {
                            HStack {
                                Text("Путь введения")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("Путь введения", selection: $routeOfAdministration) {
                                    Text("Авто").tag("")
                                    ForEach(routeOptions, id: \.self) { v in
                                        Text(v).tag(v)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(SolarizedTheme.accentColor)
                            }
                        }

                        fieldShell {
                            HStack {
                                Text("Форма выдачи")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("Форма выдачи", selection: $packagingForm) {
                                    Text("Авто").tag("")
                                    ForEach(packagingOptions, id: \.self) { v in
                                        Text(v).tag(v)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(SolarizedTheme.accentColor)
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    fieldShell {
                        HStack {
                            Text("Дополнительные настройки")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showAdvancedFields ? 90 : 0))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(SolarizedTheme.secondarySurfaceColor.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var recipeSection: some View {
        Section("Рецепт") {
            VStack(alignment: .leading, spacing: 14) {
                Text("4. Готовый рецепт")
                    .font(.subheadline.weight(.semibold))

                Picker("Формат", selection: $outputFormat) {
                    ForEach(RecipeOutputFormat.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                if outputFormat == .brand {
                    Text("Брендовый рецепт подходит не всегда: в госучреждениях обычно требуют МНН. Используй торговое название только когда это допустимо (частная практика/комиссия).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(outputText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 110, maxHeight: 220)
                .padding(10)
                .background(SolarizedTheme.surfaceColor.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SolarizedTheme.borderColor, lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button("Копировать") {
                        Haptics.tap()
                        UIPasteboard.general.string = outputText
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SolarizedTheme.accentColor)

                    Button("Сохранить рецепт") {
                        Haptics.tap()
                        saveCurrentRecipe()
                        showSavedAlert = true
                    }
                    .buttonStyle(.bordered)
                    .tint(SolarizedTheme.accentColor)
                }
                .alert("Сохранено", isPresented: $showSavedAlert) {
                    Button("OK", role: .cancel) {}
                }
            }
            .padding(12)
            .background(SolarizedTheme.secondarySurfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SolarizedTheme.borderColor, lineWidth: 1)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func saveSelectedDrugAnnotation() {
        guard let repository else { return }
        let uaVariantId = card.uaVariantId
        let formRaw = form.rawValue
        Task {
            do {
                try await repository.saveUserRecipeAnnotation(
                    uaVariantId: uaVariantId,
                    doseText: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantityN: quantityN.trimmingCharacters(in: .whitespacesAndNewlines),
                    formRaw: formRaw,
                    signaText: signa.trimmingCharacters(in: .whitespacesAndNewlines),
                    volumeText: volume.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    hasSavedAnnotations = true
                }
            } catch {
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var quickInputBinding: Binding<String>? {
        guard let activeQuickInputField else { return nil }
        switch activeQuickInputField {
        case .dosage:
            return $dosage
        case .quantity:
            return $quantityN
        case .volume:
            return $volume
        case .signa:
            return $signa
        }
    }

    @ViewBuilder
    private var quickInputOverlay: some View {
        if let activeQuickInputField, let binding = quickInputBinding {
            QuickInputAccessoryBar(
                title: activeQuickInputField.title,
                placeholder: activeQuickInputField.placeholder,
                text: binding,
                keyboardType: activeQuickInputField.keyboardType,
                tokens: activeQuickInputField.tokens
            ) {
                dismissQuickInput()
            }
            .id(activeQuickInputField)
            .padding(.horizontal, 12)
            .padding(.bottom, keyboardObserver.height > 0 ? keyboardObserver.height + 8 : 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func activateQuickInput(_ field: QuickInputField) {
        activeQuickInputField = field
    }

    private func dismissQuickInput() {
        activeQuickInputField = nil
        hideKeyboard()
    }

    private func prefill(overwrite: Bool = false) {
        prefillFromSelectedDrug(overwrite: overwrite)
    }

    private func saveCurrentRecipe() {
        let text = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let title: String = {
            let b = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
            let i = innName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty { return b }
            if !i.isEmpty { return i }
            return "Рецепт"
        }()

        let uid = session.effectiveUserId
        let item = SavedRecipeItem(title: title, text: text)
        SavedRecipesStore.add(userId: uid, item: item)
        Task {
            await SavedRecipesStore.upsertToCloud(userId: uid, item: item)
        }
    }


    private func scheduleSearch(_ text: String) {
        pendingSearchWorkItem?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            drugResults = []
            drugSearchError = nil
            isDrugSearchLoading = false
            return
        }

        let work = DispatchWorkItem { [trimmed] in
            Task { await performSearch(trimmed) }
        }
        pendingSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func performSearch(_ text: String) async {
        guard let repository else { return }
        if isSelectingDrug { return }
        isDrugSearchLoading = true
        do {
            let found = try await repository.searchCompendium(query: text, limit: 50)
            drugResults = found
            drugSearchError = nil
        } catch {
            print("Compendium search error:", error)
            drugResults = []
            drugSearchError = error.localizedDescription
        }
        isDrugSearchLoading = false
    }

    private func selectDrug(_ item: DrugSearchResult) {
        guard let repository else { return }
        if isSelectingDrug { return }
        Haptics.tap()
        isSelectingDrug = true
        hasSavedAnnotations = item.isAnnotated
        Task {
            do {
                let loaded = try await repository.loadCard(uaVariantId: item.uaVariantId)
                card = loaded
                await loadParsedPreviewIfNeeded(repository: repository, card: loaded)
                prefill(overwrite: true)
                await loadSharedRecipeIfPossible(uaVariantId: item.uaVariantId)
                drugQuery = ""
                drugResults = []
                drugSearchError = nil
            } catch {
                drugSearchError = error.localizedDescription
            }
            isSelectingDrug = false
        }
    }

    private func loadParsedPreviewIfNeeded(repository: PharmaRepository, card: DrugCard) async {
        let uaVariantId = card.uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uaVariantId.isEmpty else { return }

        await MainActor.run {
            parsedPreviewError = nil
        }

        do {
            if let cached = try await repository.loadParsedDosageCache(uaVariantId: uaVariantId),
               let bundle = RecipeParsing.decodeParsedDosageBundle(cached) {
                await MainActor.run {
                    parsedPreviewVariants = bundle.variants
                    parsedPreviewSelectedIndex = bundle.selectedIndex
                    parsedPreview = bundle.variants[bundle.selectedIndex]
                }
                return
            }

            let raw = (card.uaRegistryVariant?["form"] ?? nil)
                ?? ((card.finalRecord?["dosage_form_text"] ?? nil) ?? ((card.finalRecord?["form"] ?? nil) ?? ""))
            let comp = (card.uaRegistryVariant?["composition"] ?? nil)
                ?? ((card.finalRecord?["composition_actives"] ?? nil) ?? ((card.finalRecord?["composition"] ?? nil) ?? ""))
            let parsed = RecipeParsing.parseDosageFormTextVariants(raw: raw, composition: comp)
            let json = RecipeParsing.encodeParsedDosageBundle(variants: parsed.variants, selectedIndex: parsed.selectedIndex)
            if !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await repository.saveParsedDosageCache(uaVariantId: uaVariantId, parsedJson: json)
            }

            await MainActor.run {
                parsedPreviewVariants = parsed.variants
                parsedPreviewSelectedIndex = parsed.selectedIndex
                parsedPreview = parsed.variants[parsed.selectedIndex]
            }
        } catch {
            await MainActor.run {
                parsedPreviewError = error.localizedDescription
            }
        }
    }

    private func prefillFromSelectedDrug(overwrite: Bool = false) {
        if let repository, !card.uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                do {
                    if let row = try await repository.loadUserRecipeAnnotation(uaVariantId: card.uaVariantId) {
                        let doseText = (row["dose_text"] ?? nil) ?? ""
                        let quantity = (row["quantity_n"] ?? nil) ?? ""
                        let formRaw = (row["form_raw"] ?? nil) ?? ""
                        let signaText = (row["signa_text"] ?? nil) ?? ""
                        let volumeText = (row["volume_text"] ?? nil) ?? ""

                        let isAnnotatedNow = !doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !formRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !volumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                        await MainActor.run {
                            hasSavedAnnotations = isAnnotatedNow
                            if (overwrite || dosage.isEmpty), !doseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                dosage = doseText
                            }
                            if (overwrite || quantityN.isEmpty), !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                quantityN = quantity
                            }
                            if overwrite, !formRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                form = RecipeParsing.inferForm(from: formRaw)
                            }
                            if (overwrite || signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                               !signaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                signa = signaText
                            }
                            if (overwrite || volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                               !volumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                volume = volumeText
                            }
                        }
                    } else {
                        await MainActor.run {
                            hasSavedAnnotations = false
                        }
                    }
                } catch {
                }
            }
        }

        if overwrite || brandName.isEmpty {
            let b1 = (card.finalRecord?["brand_name_ua"] ?? nil) ?? ""
            let b2 = (card.finalRecord?["brand_name"] ?? nil) ?? ""
            let b3 = (card.uaRegistryVariant?["brand_name"] ?? nil) ?? ""
            let b4 = (card.enrichedVariant?["brand_name"] ?? nil) ?? ""
            let picked = !b1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? b1
                : (!b2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? b2
                    : (!b3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? b3 : b4))
            brandName = picked
        }

        if overwrite || innName.isEmpty {
            let i1 = (card.finalRecord?["inn"] ?? nil) ?? ""
            let i2 = (card.finalRecord?["inn_name"] ?? nil) ?? ""
            let i3 = (card.uaRegistryVariant?["inn_name"] ?? nil) ?? ""
            let picked = !i1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? i1
                : (!i2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? i2 : i3)
            innName = picked
        }

        let finalFormRaw = (card.uaRegistryVariant?["form"] ?? nil)
            ?? ((card.finalRecord?["dosage_form_text"] ?? nil) ?? ((card.finalRecord?["form"] ?? nil) ?? ""))
        let finalCompositionRaw = (card.uaRegistryVariant?["composition"] ?? nil)
            ?? ((card.finalRecord?["composition_actives"] ?? nil) ?? ((card.finalRecord?["composition"] ?? nil) ?? ""))

        let parsedBundle = RecipeParsing.parseDosageFormTextVariants(raw: finalFormRaw, composition: finalCompositionRaw)
        let parsed = parsedBundle.variants[parsedBundle.selectedIndex]

        if overwrite || dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !parsed.dosageSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dosage = parsed.dosageSuggestion
            }
        }

        if overwrite || quantityN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !parsed.quantityNSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                quantityN = parsed.quantityNSuggestion
            }
        }

        if overwrite || volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !parsed.volumeSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                volume = parsed.volumeSuggestion
            }
        }

        let formText = (card.uaRegistryVariant?["form"] ?? nil)
            ?? (card.finalRecord?["dosage_form_text"] ?? nil)
            ?? (card.finalRecord?["form"] ?? nil)
            ?? ""
        let composition = (card.uaRegistryVariant?["composition"] ?? nil)
            ?? (card.finalRecord?["composition_actives"] ?? nil)
            ?? (card.finalRecord?["composition"] ?? nil)
            ?? ""
        if overwrite || formText.isEmpty == false || composition.isEmpty == false {
            form = parsed.form
        }

        formContext = ""
        routeOfAdministration = ""
        packagingForm = ""

        let fcLower = (formText + " " + composition).lowercased()
        _ = fcLower
    }

    private func reset() {
        Haptics.tap()
        pendingSearchWorkItem?.cancel()
        pendingAutoSaveWorkItem?.cancel()
        lastAutoSavedFingerprint = ""
        drugQuery = ""
        drugResults = []
        drugSearchError = nil
        isDrugSearchLoading = false
        isSelectingDrug = false

        card = emptyCard
        brandName = ""
        innName = ""
        dosage = ""
        quantityN = ""
        volume = ""
        form = .tab
        routeOfAdministration = ""
        packagingForm = ""
        formContext = ""
        signa = ""
        outputFormat = .short

        showAdvancedFields = false
        hasSavedAnnotations = false

        sharedDoseText = ""
        sharedQuantityN = ""
        sharedFormRaw = ""
        sharedSignaText = ""
        hasSharedRecipe = false
    }

    private func scheduleAutoSave() {
        guard hasSelectedDrug else { return }
        guard repository != nil else { return }
        if isSelectingDrug { return }

        pendingAutoSaveWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task {
                await performAutoSave()
            }
        }
        pendingAutoSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func performAutoSave() async {
        guard let repository else { return }
        let uaVariantId = card.uaVariantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uaVariantId.isEmpty else { return }
        if isSelectingDrug { return }

        let payload = (
            doseText: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
            quantityN: quantityN.trimmingCharacters(in: .whitespacesAndNewlines),
            formRaw: form.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
            signaText: signa.trimmingCharacters(in: .whitespacesAndNewlines),
            volumeText: volume.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let fingerprint = [
            uaVariantId,
            payload.doseText,
            payload.quantityN,
            payload.formRaw,
            payload.signaText,
            payload.volumeText
        ].joined(separator: "|")
        if fingerprint == lastAutoSavedFingerprint { return }

        do {
            try await repository.saveUserRecipeAnnotation(
                uaVariantId: uaVariantId,
                doseText: payload.doseText,
                quantityN: payload.quantityN,
                formRaw: payload.formRaw,
                signaText: payload.signaText,
                volumeText: payload.volumeText
            )
            await MainActor.run {
                lastAutoSavedFingerprint = fingerprint
                hasSavedAnnotations = true
            }
        } catch {
        }
    }
}
