import SwiftUI
import Combine
import Darwin
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ReferenceAssistantView: View {
    @StateObject private var store: ReferenceAssistantStore
    @FocusState private var isInputFocused: Bool

    init(onOpenDestination: ((AssistantNavigationDestination) -> Void)? = nil) {
        _store = StateObject(
            wrappedValue: ReferenceAssistantStore(onOpenDestination: onOpenDestination)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if isCenteredComposerLayout {
                        VStack(spacing: 10) {
                            Spacer(minLength: 54)
                            ReferenceAssistantWelcome(
                                title: "URAN",
                                subtitle: "Ассистент-справочник по аптечной технологии",
                                description: "Спросите про правила, концентрации, бюреточную систему, фильтрацию или проверку технологии."
                            )
                            .padding(.horizontal, 18)

                            quickPromptsRow
                                .padding(.horizontal, 12)

                            inputComposer
                                .padding(.horizontal, 12)
                                .padding(.top, 2)

                            Spacer(minLength: 140)
                        }
                        .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.messages) { message in
                                ReferenceMessageBubble(
                                    message: message,
                                    onActionTap: { action in
                                        store.handleMessageAction(action)
                                        isInputFocused = false
                                    }
                                )
                                    .id(message.id)
                            }

                            if store.isSearching {
                                TimelineView(.periodic(from: .now, by: 0.7)) { context in
                                    Text(thinkingStatusText(for: context.date))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.opacity)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .transition(.opacity)
                                .id("searching_indicator")
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                }
                .background(SolarizedTheme.backgroundColor)
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: store.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: store.isSearching) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .animation(.easeInOut(duration: 0.28), value: store.messages.count)
                .animation(.easeInOut(duration: 0.22), value: store.isSearching)
            }

            if !isCenteredComposerLayout {
                Divider()

                quickPromptsRow
                    .padding(.horizontal, 12)
                    .background(SolarizedTheme.backgroundColor)

                inputComposer
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                    .background(SolarizedTheme.backgroundColor)
            }
        }
        .background(SolarizedTheme.backgroundColor)
        .navigationTitle("URAN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сброс") {
                    store.resetChat()
                    isInputFocused = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .light, design: .default))
                .foregroundStyle(Color.black)
                .disabled(store.messages.isEmpty && store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var isCenteredComposerLayout: Bool {
        store.messages.isEmpty && !store.isSearching
    }

    private var quickPromptsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.quickPrompts, id: \.self) { prompt in
                    Button(prompt) {
                        store.submit(prompt)
                        isInputFocused = false
                    }
                    .font(.system(size: 13, weight: .light, design: .default))
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 8)
        }
    }

    private var inputComposer: some View {
        HStack(spacing: 10) {
            TextField("Спросить по аптечной технологии…", text: $store.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    sendCurrentInput()
                }
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 12, padding: nil)

            if shouldShowComposerActions {
                Button {
                    isInputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!isInputFocused)

                Button {
                    sendCurrentInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(store.isSearching || store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowComposerActions)
    }

    private var shouldShowComposerActions: Bool {
        let hasInput = !store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasInput || !store.messages.isEmpty
    }

    private func sendCurrentInput() {
        guard !store.isSearching else { return }
        let trimmed = store.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.submitCurrentInput()
        isInputFocused = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let target: AnyHashable
        if store.isSearching {
            target = "searching_indicator"
        } else if let lastID = store.messages.last?.id {
            target = lastID
        } else {
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func thinkingStatusText(for date: Date) -> String {
        let states = ["думаю", "пишу", "работаю"]
        let tick = Int(date.timeIntervalSince1970 / 0.7)
        let index = ((tick % states.count) + states.count) % states.count
        return states[index]
    }
}

private struct ReferenceAssistantWelcome: View {
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 32, weight: .regular, design: .default))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.system(size: 13, weight: .light, design: .default))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
    }
}

private struct ReferenceMessageBubble: View {
    let message: ReferenceAssistantMessage
    let onActionTap: (ReferenceAssistantAction) -> Void

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        Group {
            if isUser {
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .uranCard(
                            background: SolarizedTheme.accentColor.opacity(0.15),
                            cornerRadius: 12,
                            padding: nil
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if ReferencePrescriptionMessageStyler.shouldUseStyledRendering(message.text) {
                        ReferencePrescriptionMessageText(text: message.text)
                    } else {
                        Text(message.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    if !message.actions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(message.actions) { action in
                                Button {
                                    onActionTap(action)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.caption.weight(.semibold))
                                        Text(action.title)
                                            .font(.footnote.weight(.semibold))
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 6)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(SolarizedTheme.accentColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SolarizedTheme.surfaceColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !message.hits.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(message.hits) { hit in
                                ReferenceHitCard(hit: hit)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

private struct ReferencePrescriptionMessageText: View {
    let text: String

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        ReferencePrescriptionMessageStyler.styledText(from: text)
    }
}

private enum ReferencePrescriptionMessageStyler {
    static func shouldUseStyledRendering(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("рецепт (лат.):")
            || (lower.contains("rp.:") && lower.contains("экспертиза:"))
            || lower.contains("ппк:")
    }

    static func styledText(from source: String) -> AttributedString {
        let lines = source.components(separatedBy: .newlines)
        var result = AttributedString()
        var isInsidePpk = false

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "ППК:" {
                isInsidePpk = true
            } else if isInsidePpk, trimmed.hasSuffix("):") {
                isInsidePpk = false
            }

            var line = AttributedString(rawLine)
            line.font = .system(size: 15, weight: .regular)
            line.foregroundColor = .primary

            if isHeader(trimmed) {
                line.font = .system(size: 15, weight: .bold)
                line.foregroundColor = SolarizedTheme.accentColor
            } else if isRxLine(trimmed) {
                line.font = .system(size: 15, weight: .semibold, design: .monospaced)
                line.foregroundColor = .blue
            } else if trimmed.hasPrefix("- блокирующее:") {
                line.font = .system(size: 15, weight: .semibold)
                line.foregroundColor = .red
            } else if trimmed.hasPrefix("- предупреждение:") {
                line.font = .system(size: 15, weight: .semibold)
                line.foregroundColor = .orange
            } else if isInsidePpk {
                line.font = .system(size: 14, weight: .regular, design: .monospaced)
            } else if trimmed.hasPrefix("- ") {
                line.font = .system(size: 15, weight: .medium)
            }

            if !isHeader(trimmed),
               !trimmed.hasPrefix("- блокирующее:"),
               !trimmed.hasPrefix("- предупреждение:") {
                SubstanceTokenHighlighter.apply(to: &line, source: rawLine)
            }

            result.append(line)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private static func isHeader(_ line: String) -> Bool {
        if line.isEmpty { return false }
        return [
            "Соответствие команд:",
            "Что распознано:",
            "Расчет:",
            "Экспертиза:",
            "Рецепт (лат.):",
            "ППК:"
        ].contains(line)
    }

    private static func isRxLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let lowered = line.lowercased()
        return lowered.hasPrefix("rp.:")
            || lowered.hasPrefix("d.")
            || lowered.hasPrefix("s.:")
            || lowered.hasPrefix("m. f.")
            || lowered.hasPrefix("m. d. s.")
            || lowered.hasPrefix("div.")
    }
}

private struct ReferenceHitCard: View {
    let hit: ReferenceKnowledgeHit
    @State private var isMetaExpanded = false

    private var pageText: String {
        switch (hit.pageFrom, hit.pageTo) {
        case let (from?, to?) where from == to:
            return "стр. \(from)"
        case let (from?, to?):
            return "стр. \(from)-\(to)"
        case let (from?, nil):
            return "стр. \(from)"
        default:
            return "страница не указана"
        }
    }

    private var hasPageInfo: Bool {
        hit.pageFrom != nil || hit.pageTo != nil
    }

    private var hasMeta: Bool {
        hasPageInfo || !hit.docID.isEmpty || !hit.tags.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hit.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(hit.snippet)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(6)
                .textSelection(.enabled)

            if hasMeta {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isMetaExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Тех. характеристики")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Image(systemName: isMetaExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isMetaExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        if hasPageInfo {
                            Text(pageText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !hit.docID.isEmpty {
                            Text("Источник: \(hit.docID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if !hit.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(hit.tags.prefix(6), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(SolarizedTheme.surfaceColor)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SolarizedTheme.borderColor.opacity(0.5), lineWidth: 1)
        )
    }
}

private enum ConversationInputKind {
    case greeting
    case smallTalk
    case task
    case mixed
}

private enum ConversationTaskIntent: String {
    case calculation = "CALCULATION"
    case technology = "TECHNOLOGY"
    case navigation = "NAVIGATION"
    case faq = "FAQ"
}

private struct ConversationIntentDecision {
    var kind: ConversationInputKind
    var taskIntent: ConversationTaskIntent
    var taskText: String
    var standaloneReply: String?
    var wrapperPrefix: String?
}

private struct ReferenceDialogLayer {
    private struct AssetBucket {
        var greetingTriggers: [String] = []
        var politeMarkers: [String] = []
        var smallTalkTriggers: [String] = []
        var greetingReplies: [String] = []
        var greetingFollowUpReplies: [String] = []
        var smallTalkReplies: [String] = []
        var mixedPrefixes: [String] = []
        var mixedRepeatPrefixes: [String] = []
        var calculationSignals: [String] = []
        var technologySignals: [String] = []
        var navigationSignals: [String] = []
        var taskSignals: [String] = []
    }

    private let assets: AssetBucket

    private init(assets: AssetBucket) {
        self.assets = assets
    }

    static func loadFromBundle() -> ReferenceDialogLayer {
        var assets = AssetBucket()
        let candidates: [(name: String, ext: String, subdir: String?)] = [
            ("uran_faq_300", "json", "uran_book"),
            ("uran_faq_300", "json", nil)
        ]

        var selectedURL: URL?
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext, subdirectory: candidate.subdir) {
                selectedURL = url
                break
            }
        }

        if let url = selectedURL,
           let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for raw in root {
                guard let object = raw as? [String: Any] else { continue }
                let intent = clean((object["intent"] as? String) ?? "").uppercased()
                let question = clean((object["question"] as? String) ?? "")
                let answer = clean((object["answer"] as? String) ?? "")

                switch intent {
                case "DIALOG_GREETING_TRIGGER":
                    appendUnique(question, to: &assets.greetingTriggers)
                case "DIALOG_POLITE_MARKER":
                    appendUnique(question, to: &assets.politeMarkers)
                case "DIALOG_SMALL_TALK_TRIGGER":
                    appendUnique(question, to: &assets.smallTalkTriggers)
                case "DIALOG_GREETING_REPLY":
                    appendUnique(answer, to: &assets.greetingReplies)
                case "DIALOG_GREETING_REPLY_REPEAT":
                    appendUnique(answer, to: &assets.greetingFollowUpReplies)
                case "DIALOG_SMALL_TALK_REPLY":
                    appendUnique(answer, to: &assets.smallTalkReplies)
                case "DIALOG_MIXED_PREFIX":
                    appendUnique(answer, to: &assets.mixedPrefixes)
                case "DIALOG_MIXED_PREFIX_REPEAT":
                    appendUnique(answer, to: &assets.mixedRepeatPrefixes)
                case "CALCULATION":
                    absorbSignals(from: question, into: &assets.calculationSignals)
                case "TECHNOLOGY", "PHARMA_TECH":
                    absorbSignals(from: question, into: &assets.technologySignals)
                case "NAVIGATION":
                    absorbSignals(from: question, into: &assets.navigationSignals)
                default:
                    break
                }
            }
        }

        for token in assets.calculationSignals {
            appendUnique(token, to: &assets.taskSignals)
        }
        for token in assets.technologySignals {
            appendUnique(token, to: &assets.taskSignals)
        }
        for token in assets.navigationSignals {
            appendUnique(token, to: &assets.taskSignals)
        }

        for phrase in Self.baselineGreetingTriggers {
            appendUnique(phrase, to: &assets.greetingTriggers)
        }
        for phrase in Self.baselinePoliteMarkers {
            appendUnique(phrase, to: &assets.politeMarkers)
        }
        for phrase in Self.baselineSmallTalkTriggers {
            appendUnique(phrase, to: &assets.smallTalkTriggers)
        }

        if assets.greetingTriggers.isEmpty {
            assets.greetingTriggers = [
                "привет", "здравствуйте", "добрый день", "добрый вечер",
                "доброго дня", "хай", "салют", "здрасте"
            ]
        }
        if assets.politeMarkers.isEmpty {
            assets.politeMarkers = [
                "спасибо", "благодарю", "понятно", "ок", "хорошо", "ясно", "ага", "понял"
            ]
        }
        if assets.smallTalkTriggers.isEmpty {
            assets.smallTalkTriggers = [
                "как дела", "ага понял", "понял", "понятно", "окей", "норм"
            ]
        }
        if assets.greetingReplies.isEmpty {
            assets.greetingReplies = [
                "Привет. Чем помочь?",
                "Здравствуйте. Что нужно подсказать?",
                "Добрый день. Готов помочь.",
                "Привет. Давайте разберёмся.",
                "Здравствуйте. Слушаю вас."
            ]
        }
        if assets.greetingFollowUpReplies.isEmpty {
            assets.greetingFollowUpReplies = [
                "Слушаю.",
                "Да, на связи.",
                "Готов помочь.",
                "Да, продолжаем.",
                "Чем помочь дальше?"
            ]
        }
        if assets.smallTalkReplies.isEmpty {
            assets.smallTalkReplies = [
                "Понял.",
                "Да, вижу.",
                "Хорошо, давай разберём.",
                "Спасибо.",
                "Рад помочь."
            ]
        }
        if assets.mixedPrefixes.isEmpty {
            assets.mixedPrefixes = [
                "Здравствуйте.",
                "Привет.",
                "Добрый день.",
                "Да, помогу.",
                "Отлично, разберём."
            ]
        }
        if assets.mixedRepeatPrefixes.isEmpty {
            assets.mixedRepeatPrefixes = [
                "Да,",
                "Понял,",
                "Смотрю,",
                "Хорошо,",
                "По делу:"
            ]
        }

        return ReferenceDialogLayer(assets: assets)
    }

    func decide(
        input source: String,
        hasGreetedInSession: Bool,
        variantSeed: Int
    ) -> ConversationIntentDecision {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalize(trimmed)
        let tokens = Self.tokenize(normalized)

        let hasGreeting = containsAnyPhrase(normalized, tokens: tokens, phrases: assets.greetingTriggers)
            || hasTokenWithPrefix(tokens, prefixes: Self.greetingRoots)
        let hasPolite = containsAnyPhrase(normalized, tokens: tokens, phrases: assets.politeMarkers)
        let hasSmallTalkPhrase = containsAnyPhrase(normalized, tokens: tokens, phrases: assets.smallTalkTriggers)
            || hasTokenWithPrefix(tokens, prefixes: Self.smallTalkRoots)
            || normalized.contains("как дела")
            || normalized.contains("че как")
            || normalized.contains("че нового")
        let hasQuestionMarker = trimmed.contains("?") || containsAnyPhrase(normalized, tokens: tokens, phrases: Self.questionTokens)
        let hasTaskSignal = hasQuestionMarker
            || containsAnyPhrase(normalized, tokens: tokens, phrases: assets.taskSignals)
            || containsRxPattern(normalized)
        let isGreetingOnly = isOnlyLexiconContent(normalized, phrases: assets.greetingTriggers)
        let isPoliteOnly = isOnlyLexiconContent(normalized, phrases: assets.politeMarkers)

        let kind: ConversationInputKind
        if hasGreeting && (hasTaskSignal || (!isGreetingOnly && tokens.count >= 3)) {
            kind = .mixed
        } else if hasGreeting && !hasTaskSignal {
            kind = .greeting
        } else if (hasSmallTalkPhrase || hasPolite || isPoliteOnly), !hasTaskSignal {
            kind = .smallTalk
        } else {
            kind = .task
        }

        let taskIntent = detectTaskIntent(normalized: normalized, tokens: tokens)
        let cleanedTaskText = kind == .mixed
            ? cleanedMixedTaskText(source: trimmed)
            : trimmed

        switch kind {
        case .greeting:
            let replyPool = hasGreetedInSession ? assets.greetingFollowUpReplies : assets.greetingReplies
            return ConversationIntentDecision(
                kind: .greeting,
                taskIntent: .faq,
                taskText: trimmed,
                standaloneReply: pickVariant(from: replyPool, seed: variantSeed),
                wrapperPrefix: nil
            )
        case .smallTalk:
            return ConversationIntentDecision(
                kind: .smallTalk,
                taskIntent: .faq,
                taskText: trimmed,
                standaloneReply: pickVariant(from: assets.smallTalkReplies, seed: variantSeed),
                wrapperPrefix: nil
            )
        case .mixed:
            let prefixPool = hasGreetedInSession ? assets.mixedRepeatPrefixes : assets.mixedPrefixes
            return ConversationIntentDecision(
                kind: .mixed,
                taskIntent: taskIntent,
                taskText: cleanedTaskText.isEmpty ? trimmed : cleanedTaskText,
                standaloneReply: nil,
                wrapperPrefix: pickVariant(from: prefixPool, seed: variantSeed)
            )
        case .task:
            return ConversationIntentDecision(
                kind: .task,
                taskIntent: taskIntent,
                taskText: trimmed,
                standaloneReply: nil,
                wrapperPrefix: nil
            )
        }
    }

    private func detectTaskIntent(normalized: String, tokens: [String]) -> ConversationTaskIntent {
        if containsAnyPhrase(normalized, tokens: tokens, phrases: assets.calculationSignals) {
            return .calculation
        }
        if containsAnyPhrase(normalized, tokens: tokens, phrases: assets.technologySignals) {
            return .technology
        }
        if containsAnyPhrase(normalized, tokens: tokens, phrases: assets.navigationSignals) {
            return .navigation
        }
        return .faq
    }

    private func cleanedMixedTaskText(source: String) -> String {
        var working = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = (assets.greetingTriggers + assets.politeMarkers)
            .sorted { $0.count > $1.count }

        for phrase in prefixes {
            let normalizedPhrase = Self.normalize(phrase)
            guard !normalizedPhrase.isEmpty else { continue }
            if Self.normalize(working).hasPrefix(normalizedPhrase) {
                let pattern = "^(?:\\s*[\\p{P}\\s]*)" + NSRegularExpression.escapedPattern(for: phrase) + "(?:[\\p{P}\\s]*)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(
                    in: working,
                    options: [],
                    range: NSRange(location: 0, length: working.utf16.count)
                   ),
                   let range = Range(match.range, in: working) {
                    working.removeSubrange(range)
                    working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let separators = [",", ".", "!", "?", ":", ";", "-", "—", "–"]
        while let first = working.first, separators.contains(String(first)) {
            working.removeFirst()
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return working
    }

    private func containsRxPattern(_ normalized: String) -> Bool {
        if normalized.contains("rp.") || normalized.contains("rp:") || normalized.contains("возьми") {
            return true
        }
        if normalized.range(
            of: #"\d+(?:[.,]\d+)?\s*(?:мл|ml|г|гр|g|л|l|мг|mg)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    private func hasTokenWithPrefix(_ tokens: [String], prefixes: [String]) -> Bool {
        tokens.contains { token in
            prefixes.contains { prefix in token.hasPrefix(prefix) }
        }
    }

    private func containsAnyPhrase(_ normalized: String, tokens: [String], phrases: [String]) -> Bool {
        for raw in phrases {
            let phrase = Self.normalize(raw)
            guard !phrase.isEmpty else { continue }
            if phrase.contains(" ") {
                if normalized.contains(phrase) {
                    return true
                }
            } else if tokens.contains(phrase) {
                return true
            }
        }
        return false
    }

    private func isOnlyLexiconContent(_ normalized: String, phrases: [String]) -> Bool {
        guard !normalized.isEmpty else { return false }
        var cleaned = normalized
        for raw in phrases.sorted(by: { $0.count > $1.count }) {
            let phrase = Self.normalize(raw)
            if phrase.isEmpty { continue }
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ")
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return cleaned.isEmpty
    }

    private func pickVariant(from variants: [String], seed: Int) -> String {
        let pool = variants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pool.isEmpty else { return "Понял." }
        let index = abs(seed) % pool.count
        return pool[index]
    }

    private static let questionTokens: [String] = [
        "как", "что", "где", "когда", "зачем", "почему", "сколько",
        "какой", "какая", "какие", "подскажи", "рассчитай", "посчитай"
    ]

    private static let baselineGreetingTriggers: [String] = [
        "привет", "здравствуй", "здравствуйте", "здрасте", "добрый день", "добрый вечер",
        "хай", "салют", "здорова", "здарова", "здаров", "ку", "йо", "hello", "hi"
    ]

    private static let baselinePoliteMarkers: [String] = [
        "спасибо", "благодарю", "понятно", "понял", "ясно", "ок", "окей", "ага"
    ]

    private static let baselineSmallTalkTriggers: [String] = [
        "как дела", "че как", "че нового", "норм", "нормально", "понял", "понятно"
    ]

    private static let greetingRoots: [String] = [
        "привет", "здрав", "здоров", "здаров", "хай", "салют", "добр", "hello", "hi", "ку"
    ]

    private static let smallTalkRoots: [String] = [
        "спасиб", "благодар", "понят", "понял", "ясн", "норм", "ок", "ага"
    ]

    private static let signalStopWords: Set<String> = [
        "как", "что", "где", "когда", "или", "для", "это", "надо",
        "можно", "ли", "про", "по", "в", "на", "с", "из", "до", "и", "а"
    ]

    private static func absorbSignals(from question: String, into destination: inout [String]) {
        let normalized = normalize(question)
        let tokens = tokenize(normalized)
        for token in tokens where token.count >= 3 && !signalStopWords.contains(token) {
            appendUnique(token, to: &destination)
        }
    }

    private static func appendUnique(_ value: String, to destination: inout [String]) {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return }
        if !destination.contains(cleaned) {
            destination.append(cleaned)
        }
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ text: String) -> String {
        clean(text)
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func tokenize(_ normalized: String) -> [String] {
        normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .reduce(into: [String]()) { out, token in
                if !out.contains(token) {
                    out.append(token)
                }
            }
    }
}

@MainActor
private final class ReferenceAssistantStore: ObservableObject {
    private enum CasualTopic {
        case weather
        case time
        case identity
    }

    private enum CompendiumSection: String {
        case composition = "Composition"
        case dosageForm = "Dosage Form"
        case pharmacologicalProperties = "Pharmacological Properties"
        case indications = "Indications"
        case dosageAdministration = "Dosage & Administration"
        case contraindications = "Contraindications"
        case sideEffects = "Side Effects"
        case interactions = "Interactions"
        case overdose = "Overdose"
        case storageConditions = "Storage Conditions"
    }

    private enum CompendiumAudience {
        case pediatric
        case adult
    }

    private enum CalcFlowType {
        case solutionPercent
        case dilution
    }

    private enum CalcFlowStep {
        case selectFlow
        case solutionConcentration
        case solutionVolume
        case dilutionStockConcentration
        case dilutionTargetConcentration
        case dilutionTargetVolume
    }

    private struct RecipeCalcSession {
        var flow: CalcFlowType?
        var step: CalcFlowStep
        var concentrationPercent: Double?
        var volumeMl: Double?
        var stockPercent: Double?
        var targetPercent: Double?
        var targetVolumeMl: Double?
    }

    private struct ParsedIngredientLine {
        var ingredient: IngredientDraft
        var sourceText: String
        var volumeMl: Double?
        var concentrationPercent: Double?
        var dilutionDenominator: Double?
        var reference: PrescriptionSubstanceCatalog.Entry?
    }

    private struct ParsedPrescription {
        var draft: ExtempRecipeDraft
        var signaText: String
        var parsedIngredients: [ParsedIngredientLine]
        var numero: Int?
    }

    @Published var messages: [ReferenceAssistantMessage] = []
    @Published var inputText: String = ""
    @Published var isSearching = false

    private let responseDelayNs: UInt64 = 2_000_000_000
    private let extraInfoDelayNs: UInt64 = 1_000_000_000
    private let revealInfoDelayNs: UInt64 = 700_000_000
    let quickPrompts: [String] = [
        "Бюреточные рецепты",
        "Стандартные растворы",
        "Рецепт Люголя",
        "Правило 3% для растворов"
    ]

    private let service: ReferenceKnowledgeSearchService
    private let ruleEngine: RuleEngineProtocol
    private let outputPipeline = RxOutputPipeline()
    private let dialogLayer: ReferenceDialogLayer
    private let substanceCatalog = PrescriptionSubstanceCatalog.loadFromBundle()
    private let smallTalkService = LocalSmallTalkLLMService.shared
    private let onOpenDestination: ((AssistantNavigationDestination) -> Void)?
    private var responseTask: Task<Void, Never>?
    private var calcSession: RecipeCalcSession?
    private var hasGreetedInSession = false
    private var dialogVariantSeed = 0
    private var lastCasualTopic: CasualTopic?
    private var pendingCompendiumQuery: String?

    init(
        service: ReferenceKnowledgeSearchService = .shared,
        ruleEngine: RuleEngineProtocol? = nil,
        onOpenDestination: ((AssistantNavigationDestination) -> Void)? = nil
    ) {
        self.service = service
        self.ruleEngine = ruleEngine ?? DefaultRuleEngine()
        self.dialogLayer = ReferenceDialogLayer.loadFromBundle()
        self.onOpenDestination = onOpenDestination
        self.messages = []
    }

    func submitCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSearching else { return }
        inputText = ""
        submit(text)
    }

    func submit(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }

        responseTask?.cancel()
        messages.append(ReferenceAssistantMessage(role: .user, text: trimmed, hits: [], actions: []))

        dialogVariantSeed += 1
        let decision = dialogLayer.decide(
            input: trimmed,
            hasGreetedInSession: hasGreetedInSession,
            variantSeed: dialogVariantSeed
        )

        switch decision.kind {
        case .greeting:
            hasGreetedInSession = true
            replyForCasualDialog(
                userInput: trimmed,
                fallback: fallbackForCasualDialog(
                    input: trimmed,
                    defaultResponse: decision.standaloneReply ?? "Я Uran, на связи )) Что разбираем?"
                )
            )
            return
        case .smallTalk:
            replyForCasualDialog(
                userInput: trimmed,
                fallback: fallbackForCasualDialog(
                    input: trimmed,
                    defaultResponse: decision.standaloneReply ?? "Я понял тебя ))"
                )
            )
            return
        case .task, .mixed:
            break
        }

        if decision.kind == .mixed {
            hasGreetedInSession = true
        }

        let effectiveQuestion = decision.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? trimmed
            : decision.taskText
        let conversationalPrefix = decision.wrapperPrefix

        if shouldForceCasualDialog(input: effectiveQuestion, taskIntent: decision.taskIntent) {
            replyForCasualDialog(
                userInput: trimmed,
                fallback: fallbackForCasualDialog(
                    input: trimmed,
                    defaultResponse: "Я Uran, на связи )) Чем помочь по задаче?"
                )
            )
            return
        }

        if handleNavigationShortcut(
            input: effectiveQuestion,
            wrapperPrefix: conversationalPrefix,
            taskIntent: decision.taskIntent
        ) {
            return
        }

        if handlePrescriptionAnalysis(input: effectiveQuestion, wrapperPrefix: conversationalPrefix) {
            return
        }

        if handleCalculationFlow(input: effectiveQuestion, wrapperPrefix: conversationalPrefix) {
            return
        }

        if handleCompendiumInstruction(input: effectiveQuestion, wrapperPrefix: conversationalPrefix) {
            return
        }

        isSearching = true

        responseTask = Task {
            try? await Task.sleep(nanoseconds: responseDelayNs)
            if Task.isCancelled { return }

            let response = await service.answer(for: effectiveQuestion, limit: 4)
            if Task.isCancelled { return }
            let generatedReply = await smallTalkService.replyWithKnowledge(
                userInput: effectiveQuestion,
                hits: response.hits
            )
            if Task.isCancelled { return }
            await MainActor.run {
                isSearching = false
                let actions = navigationActions(
                    for: effectiveQuestion,
                    taskIntent: decision.taskIntent,
                    hits: response.hits
                )
                let responseText = generatedReply ?? response.answerText
                withAnimation(.easeInOut(duration: 0.28)) {
                    messages.append(
                        ReferenceAssistantMessage(
                            role: .assistant,
                            text: composeConversationalReply(
                                prefix: conversationalPrefix,
                                coreText: responseText
                            ),
                            hits: response.hits.isEmpty ? [] : [response.hits[0]],
                            actions: actions
                        )
                    )
                }
            }

            let extraHits = Array(response.hits.dropFirst())
            guard !extraHits.isEmpty else {
                await MainActor.run { responseTask = nil }
                return
            }

            try? await Task.sleep(nanoseconds: extraInfoDelayNs)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.24)) {
                    messages.append(
                        ReferenceAssistantMessage(
                            role: .assistant,
                            text: "Я нашёл ещё материалы из книги, показать ))?",
                            hits: [],
                            actions: []
                        )
                    )
                }
            }

            try? await Task.sleep(nanoseconds: revealInfoDelayNs)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.28)) {
                    messages.append(
                        ReferenceAssistantMessage(
                            role: .assistant,
                            text: "Показываю доп.фрагменты, вдруг пригодится )):",
                            hits: extraHits,
                            actions: []
                        )
                    )
                }
                responseTask = nil
            }
        }
    }

    private func replyForCasualDialog(userInput: String, fallback: String) {
        isSearching = true
        responseTask = Task {
            let llmReply = await smallTalkService.reply(
                userInput: userInput,
                history: messages
            )
            if Task.isCancelled { return }
            await MainActor.run {
                isSearching = false
                appendAssistantText(llmReply ?? fallback)
                responseTask = nil
            }
        }
    }

    func resetChat() {
        responseTask?.cancel()
        responseTask = nil
        Task { await smallTalkService.reset() }
        calcSession = nil
        lastCasualTopic = nil
        pendingCompendiumQuery = nil
        hasGreetedInSession = false
        dialogVariantSeed = 0
        messages = []
        inputText = ""
        isSearching = false
    }

    func handleMessageAction(_ action: ReferenceAssistantAction) {
        switch action.kind {
        case .compendiumSelection(let id):
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryForSelection = pendingCompendiumQuery ?? title
            responseTask?.cancel()
            if !title.isEmpty {
                messages.append(
                    ReferenceAssistantMessage(
                        role: .user,
                        text: title,
                        hits: [],
                        actions: []
                    )
                )
            }
            isSearching = true
            responseTask = Task {
                try? await sendCompendiumDetails(for: id, wrapperPrefix: nil, userQuery: queryForSelection)
            }
        case .openAppDestination(let destination):
            onOpenDestination?(destination)
            if onOpenDestination == nil {
                appendAssistantText("Переход по разделам доступен из главного экрана приложения.")
            }
        }
    }

    private func handleNavigationShortcut(
        input: String,
        wrapperPrefix: String?,
        taskIntent: ConversationTaskIntent
    ) -> Bool {
        guard !isPrescriptionInputCandidate(input) else { return false }

        let normalized = normalizeNavigationQuery(input)
        let shouldHandle = taskIntent == .navigation || isNavigationRouteQuestion(normalizedQuery: normalized)
        guard shouldHandle else { return false }

        var destinations = inferNavigationDestinations(
            normalizedQuery: normalized,
            hits: []
        )
        if destinations.isEmpty {
            destinations = defaultNavigationDestinations
        }

        let actions = makeNavigationActions(for: destinations)
        let coreText: String
        if destinations.count == 1, let only = destinations.first {
            coreText = "Нажмите ссылку ниже, чтобы открыть раздел \(only.sectionTitle)."
        } else {
            let names = destinations.map(\.sectionTitle).joined(separator: ", ")
            coreText = "Вот быстрые переходы: \(names). Нажмите нужную ссылку."
        }

        appendAssistantMessage(
            composeConversationalReply(prefix: wrapperPrefix, coreText: coreText),
            hits: [],
            actions: actions
        )
        return true
    }

    private func navigationActions(
        for question: String,
        taskIntent: ConversationTaskIntent,
        hits: [ReferenceKnowledgeHit]
    ) -> [ReferenceAssistantAction] {
        let normalized = normalizeNavigationQuery(question)
        let shouldOffer = taskIntent == .navigation
            || hits.contains(where: isAppNavigationHit)
            || isNavigationRouteQuestion(normalizedQuery: normalized)
        guard shouldOffer else { return [] }

        var destinations = inferNavigationDestinations(
            normalizedQuery: normalized,
            hits: hits
        )
        if destinations.isEmpty {
            destinations = defaultNavigationDestinations
        }

        return makeNavigationActions(for: destinations)
    }

    private func inferNavigationDestinations(
        normalizedQuery: String,
        hits: [ReferenceKnowledgeHit]
    ) -> [AssistantNavigationDestination] {
        var collected: [AssistantNavigationDestination] = []

        for hit in hits {
            for destination in mapAppHintHitToDestinations(hitID: hit.id) {
                appendUnique(destination, to: &collected)
            }
        }

        if containsAny(in: normalizedQuery, terms: ["поиск", "search", "найти препарат", "лекарств"]) {
            appendUnique(.search, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["рецепт", "recipes", "экстемп", "ппк", "бюрет", "спирт", "калькулятор"]) {
            appendUnique(.recipes, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["форум", "обсуждени", "thread"]) {
            appendUnique(.forum, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["вики", "wiki", "заметк"]) {
            appendUnique(.wiki, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["сообщени", "чат", "messages", "диалог"]) {
            appendUnique(.messages, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["групп", "команд"]) {
            appendUnique(.groups, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["профил", "аккаунт", "настройк"]) {
            appendUnique(.profile, to: &collected)
        }
        if containsAny(in: normalizedQuery, terms: ["ассистент", "справочник"]) {
            appendUnique(.assistant, to: &collected)
        }

        return collected
    }

    private func mapAppHintHitToDestinations(hitID: String) -> [AssistantNavigationDestination] {
        switch hitID {
        case "app-ethanol_calc", "app-create_recipe":
            return [.recipes]
        case "app-drug_search":
            return [.search]
        case "app-forum_wiki":
            return [.forum, .wiki]
        case "app-app_capabilities":
            return defaultNavigationDestinations
        default:
            return []
        }
    }

    private func makeNavigationActions(
        for destinations: [AssistantNavigationDestination]
    ) -> [ReferenceAssistantAction] {
        destinations.map { destination in
            ReferenceAssistantAction(
                title: destination.actionTitle,
                kind: .openAppDestination(destination: destination)
            )
        }
    }

    private func isAppNavigationHit(_ hit: ReferenceKnowledgeHit) -> Bool {
        hit.id.hasPrefix("app-") || hit.tags.contains("APP_NAVIGATION")
    }

    private func isNavigationRouteQuestion(normalizedQuery: String) -> Bool {
        let hasRouteCue = containsAny(
            in: normalizedQuery,
            terms: [
                "как открыть",
                "как перейти",
                "где находится",
                "где найти",
                "куда нажать",
                "в какой вкладке",
                "какой раздел",
                "открыть раздел",
                "перейти в",
                "вкладк",
                "раздел",
                "меню",
                "экран"
            ]
        )
        let hasSectionMention = containsAny(
            in: normalizedQuery,
            terms: [
                "поиск",
                "search",
                "recipes",
                "рецепт",
                "экстемп",
                "форум",
                "вики",
                "wiki",
                "сообщени",
                "чат",
                "групп",
                "профил",
                "ассистент"
            ]
        )
        return hasRouteCue && hasSectionMention
    }

    private func normalizeNavigationQuery(_ source: String) -> String {
        source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    private func containsAny(in source: String, terms: [String]) -> Bool {
        terms.contains { source.contains($0) }
    }

    private func appendUnique(
        _ destination: AssistantNavigationDestination,
        to list: inout [AssistantNavigationDestination]
    ) {
        if !list.contains(destination) {
            list.append(destination)
        }
    }

    private var defaultNavigationDestinations: [AssistantNavigationDestination] {
        [.search, .recipes, .forum, .wiki, .messages, .groups, .profile]
    }

    private func handlePrescriptionAnalysis(input: String, wrapperPrefix: String? = nil) -> Bool {
        guard isPrescriptionInputCandidate(input) else { return false }

        guard let parsed = parsePrescription(from: input) else {
            appendAssistantText(
                composeConversationalReply(
                    prefix: wrapperPrefix,
                    coreText: """
Не смог уверенно разобрать пропись.
Вставьте рецепт в формате:
`Возьми: ...`
`Дай. Обозначь: ...`
"""
                )
            )
            return true
        }

        calcSession = nil
        isSearching = true
        responseTask = Task {
            try? await Task.sleep(nanoseconds: responseDelayNs)
            if Task.isCancelled { return }

            let answer = buildPrescriptionAnswer(from: parsed)
            if Task.isCancelled { return }

            await MainActor.run {
                isSearching = false
                appendAssistantText(
                    composeConversationalReply(
                        prefix: wrapperPrefix,
                        coreText: answer
                    )
                )
                responseTask = nil
            }
        }
        return true
    }

    private func isPrescriptionInputCandidate(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let hasMarker = normalized.contains("возьми")
            || normalized.contains("rp.")
            || normalized.contains("rp:")
            || normalized.contains("обознач")
            || normalized.contains("d.s")
            || normalized.contains("m.d.s")
            || normalized.contains("d.t.d")
            || normalized.contains("выдай")
        let hasMeasure = normalized.range(
            of: #"\d+(?:[.,]\d+)?\s*(?:мл|ml|г|гр|g|л|l|мг|mg)\b"#,
            options: .regularExpression
        ) != nil
        let hasPercent = normalized.range(
            of: #"\d+(?:[.,]\d+)?\s*%"#,
            options: .regularExpression
        ) != nil
        let hasRatio = normalized.range(
            of: #"(?<!\d)1\s*[:/]\s*\d+(?:[.,]\d+)?"#,
            options: .regularExpression
        ) != nil
        let hasBareMass = normalized.range(
            of: #"[а-яa-zё][^,\n;:]{1,80}\s\d+(?:[.,]\d+)?\s*$"#,
            options: .regularExpression
        ) != nil
        return hasMarker && (hasMeasure || hasRatio || hasPercent || hasBareMass)
    }

    private func parsePrescription(from source: String) -> ParsedPrescription? {
        let cleaned = source
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let signaText = parseSigna(from: cleaned)
        let composition = extractCompositionBlock(from: cleaned)
        let rawLines = composition
            .split(separator: "\n")
            .map { String($0) }
            .flatMap { line -> [String] in
                line
                    .split(separator: ";")
                    .map { String($0) }
            }

        var parsedIngredients: [ParsedIngredientLine] = []
        for rawLine in rawLines {
            if let parsed = parseIngredientLine(rawLine) {
                parsedIngredients.append(parsed)
            }
        }

        guard !parsedIngredients.isEmpty else { return nil }

        var draft = ExtempRecipeDraft()
        draft.patientName = "Ассистент"
        draft.rxNumber = "assistant"
        draft.signa = signaText
        draft.ingredients = parsedIngredients.map(\.ingredient)
        draft.numero = parseNumero(from: cleaned)

        if parsedIngredients.contains(where: { $0.ingredient.presentationKind == .solution }) {
            draft.formMode = .solutions
        }

        if let firstVolume = parsedIngredients.first(where: { $0.volumeMl != nil })?.volumeMl,
           firstVolume > 0 {
            draft.targetValue = firstVolume
            draft.targetUnit = UnitCode(rawValue: "ml")
            draft.solVolumeMl = firstVolume
        }

        if let firstPercent = parsedIngredients.first(where: {
            $0.ingredient.presentationKind == .solution && $0.concentrationPercent != nil
        })?.concentrationPercent,
           firstPercent > 0 {
            draft.solPercent = firstPercent
            draft.solPercentInputText = formatDouble(firstPercent)
        }

        let signaLower = signaText.lowercased()
        if signaLower.contains("глаз") {
            draft.isOphthalmicDrops = true
            draft.formMode = .drops
        }

        return ParsedPrescription(
            draft: draft,
            signaText: signaText,
            parsedIngredients: parsedIngredients,
            numero: draft.numero
        )
    }

    private func parseSigna(from text: String) -> String {
        let patterns = [
            #"(?is)(?:обознач(?:ь)?\.?\s*:?)\s*(.+)$"#,
            #"(?is)(?:d\s*\.?\s*s\s*\.?\s*:?)\s*(.+)$"#,
            #"(?is)(?:m\s*\.?\s*d\s*\.?\s*s\s*\.?\s*:?)\s*(.+)$"#,
            #"(?is)(?:signa\s*:?)\s*(.+)$"#
        ]

        for pattern in patterns {
            if let candidate = firstRegexCapture(in: text, pattern: pattern) {
                let normalized = normalizeSpacing(candidate)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        return ""
    }

    private func extractCompositionBlock(from text: String) -> String {
        let pattern = #"(?is)(?:возьми|rp\.?\s*:?)\s*[:.]?\s*(.+?)\s*(?:дай\.?|обознач(?:ь)?\.?|d\s*\.?\s*s\s*\.?\s*:?|m\s*\.?\s*d\s*\.?\s*s\s*\.?\s*:?|signa\s*:?|$)"#
        if let match = firstRegexCapture(in: text, pattern: pattern) {
            return normalizeSpacingKeepingLines(match)
        }

        let fallback = text
            .components(separatedBy: .newlines)
            .filter { line in
                let lower = line.lowercased()
                return !lower.contains("дай")
                    && !lower.contains("обознач")
                    && !lower.contains("d.s")
            }
            .joined(separator: "\n")
        return normalizeSpacingKeepingLines(fallback)
    }

    private func parseIngredientLine(_ source: String) -> ParsedIngredientLine? {
        let line = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•*"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-–—"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        guard let amountTail = parseAmountTail(from: line) else { return nil }
        let rawValue = amountTail.valueText.replacingOccurrences(of: ",", with: ".")
        guard let parsedValue = Double(rawValue), parsedValue > 0 else { return nil }

        var amount = parsedValue
        let unitCode: UnitCode = {
            guard let rawUnit = amountTail.unitText?.lowercased() else {
                return UnitCode(rawValue: "g")
            }
            switch rawUnit {
            case "л", "l", "литр", "литра", "литров":
                amount = parsedValue * 1_000
                return UnitCode(rawValue: "ml")
            case "мг", "mg":
                amount = parsedValue / 1_000
                return UnitCode(rawValue: "g")
            case "г", "гр", "g", "грамм", "грамма", "граммов":
                return UnitCode(rawValue: "g")
            case "мл", "ml", "миллилитр", "миллилитра", "миллилитров":
                return UnitCode(rawValue: "ml")
            default:
                return UnitCode(rawValue: "g")
            }
        }()

        let namePart = String(line.prefix(upTo: amountTail.fullRange.lowerBound))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-,.;-–—"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !namePart.isEmpty else { return nil }

        let lowerName = namePart.lowercased()
        let isAd = lowerName.hasPrefix("ad ")
            || lowerName.contains(" ad ")
            || lowerName.hasPrefix("до ")
            || lowerName.contains(" до ")
        let isQs = lowerName.contains("q.s")
        let concentration = parsePercentValue(from: line)
        let dilution = parseDilutionDenominator(from: line)
        let isEthanolStrength = isEthanolStrengthNotation(
            nameLowercased: lowerName,
            unit: unitCode,
            concentrationPercent: concentration
        )
        let isSolution = (hasSolutionMarker(in: lowerName)
            || concentration != nil
            || dilution != nil) && !isEthanolStrength
        let normalizedName = normalizeIngredientName(rawName: namePart)
        let resolved = isAd || isQs ? nil : substanceCatalog.bestMatch(for: normalizedName, preferSolution: isSolution)
        let resolvedNameRu = (resolved?.nameRu ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ethanolStrengthDisplayRu: String? = {
            guard isEthanolStrength, let concentration else { return nil }
            return "Этанол \(formatDouble(concentration))%"
        }()
        let ethanolStrengthLatNom: String? = {
            guard isEthanolStrength, let concentration else { return nil }
            return "Spiritus aethylicus \(formatDouble(concentration))%"
        }()
        let ethanolStrengthLatGen: String? = {
            guard isEthanolStrength, let concentration else { return nil }
            return "Spiritus aethylici \(formatDouble(concentration))%"
        }()

        let ingredient = IngredientDraft(
            substanceId: resolved?.id,
            displayName: ethanolStrengthDisplayRu ?? (resolvedNameRu.isEmpty ? normalizedName : resolvedNameRu),
            role: role(forReferenceType: resolved?.type),
            amountValue: amount,
            unit: unitCode,
            scope: .total,
            isQS: isQs,
            isAd: isAd,
            presentationKind: isSolution ? .solution : .substance,
            rpPrefix: isSolution ? .sol : IngredientRpPrefix.none,
            refType: resolved?.type,
            refNameLatNom: ethanolStrengthLatNom ?? resolved?.nameLatNom,
            refNameLatGen: ethanolStrengthLatGen ?? resolved?.nameLatGen
        )

        let volumeMl = unitCode.rawValue == "ml" ? amount : nil

        return ParsedIngredientLine(
            ingredient: ingredient,
            sourceText: line,
            volumeMl: volumeMl,
            concentrationPercent: concentration,
            dilutionDenominator: dilution,
            reference: resolved
        )
    }

    private func parseNumero(from text: String) -> Int? {
        let patterns = [
            #"(?is)d\s*\.?\s*t\s*\.?\s*d\s*\.?\s*(?:n|№|no|number)?\s*[:.]?\s*(\d{1,3})"#,
            #"(?is)выдай(?:\s+такими\s+дозами)?\s*(?:n|№|no|номер(?:ом)?)?\s*[:.]?\s*(\d{1,3})"#,
            #"(?is)дай(?:\s+такими\s+дозами)?\s*(?:n|№|no|номер(?:ом)?)\s*[:.]?\s*(\d{1,3})"#
        ]
        for pattern in patterns {
            guard let captured = firstRegexCapture(in: text, pattern: pattern),
                  let numero = Int(captured),
                  numero > 0 else { continue }
            return numero
        }
        return nil
    }

    private func parseAmountTail(from line: String) -> (valueText: String, unitText: String?, fullRange: Range<String.Index>)? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(мл|ml|миллилитр(?:а|ов)?|г|гр|грамм(?:а|ов)?|g|л|l|литр(?:а|ов)?|мг|mg)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: line),
              let fullRange = Range(match.range(at: 0), in: line) else {
            return nil
        }

        let unitText: String?
        if match.range(at: 2).location != NSNotFound, let unitRange = Range(match.range(at: 2), in: line) {
            let raw = String(line[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            unitText = raw.isEmpty ? nil : raw
        } else {
            unitText = nil
        }

        return (
            valueText: String(line[valueRange]),
            unitText: unitText,
            fullRange: fullRange
        )
    }

    private func buildPrescriptionAnswer(from parsed: ParsedPrescription) -> String {
        let ruleResult = ruleEngine.evaluate(draft: parsed.draft)
        let output = outputPipeline.render(
            draft: ruleResult.normalizedDraft,
            derived: ruleResult.derived,
            issues: ruleResult.issues,
            techPlan: ruleResult.techPlan,
            config: RxOutputRenderConfig(showPpkSteps: true, showExtendedTech: true)
        )
        let filteredIssues = ruleResult.issues.filter {
            $0.code != "patient.name.required" && $0.code != "patient.rxNumber.required"
        }
        let expertiseSummary = ExtempFormExpertiseAnalyzer.summarize(draft: ruleResult.normalizedDraft)

        let latinRecipe = extractLatinRecipeBlock(from: output.rxText)
        var lines: [String] = []
        lines.append("Разобрал рецепт и выполнил расчёт.")
        lines.append("")
        lines.append("Что распознано:")
        lines.append("- веществ: \(parsed.parsedIngredients.count)")
        if parsed.draft.formMode == .solutions {
            lines.append("- форма: раствор")
        }
        if let numero = parsed.numero {
            lines.append("- номер выдачи (D.t.d.): \(numero)")
        }
        if !parsed.signaText.isEmpty {
            lines.append("- Signa: \(parsed.signaText)")
        }

        let calcLines = buildCalculationLines(from: parsed.parsedIngredients)
        if !calcLines.isEmpty {
            lines.append("")
            lines.append("Расчет:")
            lines.append(contentsOf: calcLines.map { "- \($0)" })
        }

        let blocking = filteredIssues.filter { $0.severity == .blocking }
        let warnings = filteredIssues.filter { $0.severity == .warning }
        let info = filteredIssues.filter { $0.severity == .info }

        lines.append("")
        lines.append("Экспертиза:")
        if let title = expertiseSummary?.title, !title.isEmpty {
            lines.append("- похоже на: \(title)")
        }
        if blocking.isEmpty && warnings.isEmpty && info.isEmpty {
            lines.append("- критичных замечаний не найдено")
        } else {
            if !blocking.isEmpty {
                lines.append(contentsOf: blocking.prefix(3).map { "- блокирующее: \($0.message)" })
            }
            if !warnings.isEmpty {
                lines.append(contentsOf: warnings.prefix(4).map { "- предупреждение: \($0.message)" })
            }
            if !info.isEmpty {
                lines.append(contentsOf: info.prefix(2).map { "- заметка: \($0.message)" })
            }
        }

        if !latinRecipe.isEmpty {
            lines.append("")
            lines.append("Рецепт (лат.):")
            lines.append(latinRecipe)
        }

        let ppkText = output.ppkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ppkText.isEmpty {
            lines.append("")
            lines.append("ППК:")
            lines.append(ppkText)
        }
        return lines.joined(separator: "\n")
    }

    private func extractLatinRecipeBlock(from rawRxText: String) -> String {
        let rawLines = rawRxText.components(separatedBy: .newlines)
        guard !rawLines.isEmpty else { return "" }

        let normalized = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let startIndex = normalized.firstIndex(where: { $0.lowercased().hasPrefix("rp.:") }) else {
            return rawRxText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let recipeLines = rawLines[startIndex...]
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return recipeLines.joined(separator: "\n")
    }

    private func buildCalculationLines(from parsed: [ParsedIngredientLine]) -> [String] {
        var result: [String] = []
        for item in parsed {
            guard let volume = item.volumeMl, volume > 0 else { continue }
            if item.ingredient.presentationKind != .solution,
               hasEthanolMarker(in: item.ingredient.displayName.lowercased()) {
                continue
            }
            let label = item.ingredient.displayName

            if let dilution = item.dilutionDenominator, dilution > 0 {
                let mass = volume / dilution
                let percent = 100.0 / dilution
                result.append(
                    "\(label): 1:\(formatDouble(dilution)) при V=\(formatDouble(volume)) мл -> вещества \(formatDouble(mass)) г (\(formatDouble(percent))%)"
                )
                continue
            }

            if let concentration = item.concentrationPercent, concentration > 0 {
                let mass = concentration * volume / 100.0
                result.append(
                    "\(label): C=\(formatDouble(concentration))%, V=\(formatDouble(volume)) мл -> вещества \(formatDouble(mass)) г"
                )
            }
        }
        return result
    }

    private func parsePercentValue(from text: String) -> Double? {
        guard let matched = firstRegexCapture(in: text, pattern: #"(\d+(?:[.,]\d+)?)\s*%"#) else { return nil }
        return Double(matched.replacingOccurrences(of: ",", with: "."))
    }

    private func hasSolutionMarker(in text: String) -> Bool {
        if text.contains("раствор") || text.contains("раствора") {
            return true
        }
        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact.contains("р-р") || compact.contains("р-ра") || compact.contains("рр") {
            return true
        }
        return text.contains("sol.")
            || text.contains("sol ")
            || text.contains("solution")
    }

    private func isEthanolStrengthNotation(
        nameLowercased: String,
        unit: UnitCode,
        concentrationPercent: Double?
    ) -> Bool {
        guard unit.rawValue.lowercased() == "ml",
              let concentrationPercent,
              concentrationPercent > 0 else {
            return false
        }
        return hasEthanolMarker(in: nameLowercased)
    }

    private func hasEthanolMarker(in text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "ё", with: "е")
        return normalized.contains("спирт этил")
            || normalized.contains("спирт етил")
            || normalized.contains("этанол")
            || normalized.contains("етанол")
            || normalized.contains("spiritus aethylic")
            || normalized.contains("spiritus vini")
            || normalized.contains("ethanol")
            || normalized.contains("alcohol aethylic")
            || normalized.contains("ethyl alcohol")
    }

    private func normalizeIngredientName(rawName: String) -> String {
        var base = rawName
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^\s*раствора?\s+"#,
            #"(?i)^\s*р-ра?\s+"#,
            #"(?i)^\s*р-р\s+"#,
            #"(?i)^\s*sol\.?\s+"#,
            #"(?i)\s*\d+(?:[.,]\d+)?\s*%\s*[-]*\s*$"#,
            #"(?i)\s*(?<!\d)1\s*[:/]\s*\d+(?:[.,]\d+)?\s*[-]*\s*$"#,
            #"(?i)\s*[-]+\s*$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(
                in: base,
                options: [],
                range: NSRange(location: 0, length: base.utf16.count)
               ),
               match.range.location != NSNotFound,
               let range = Range(match.range, in: base) {
                base.removeSubrange(range)
            }
        }

        base = base
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-,.; "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "Substantia"
        }
        return base
    }

    private func role(forReferenceType rawType: String?) -> IngredientRole {
        let normalized = (rawType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "act":
            return .active
        case "base":
            return .base
        case "solv", "solvent", "liquidstandard":
            return .solvent
        default:
            return .other
        }
    }

    private func parseDilutionDenominator(from text: String) -> Double? {
        guard let matched = firstRegexCapture(
            in: text,
            pattern: #"(?<!\d)1\s*[:/]\s*(\d+(?:[.,]\d+)?)"#
        ) else {
            return nil
        }
        return Double(matched.replacingOccurrences(of: ",", with: "."))
    }

    private func normalizeSpacing(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSpacingKeepingLines(_ text: String) -> String {
        text
            .split(separator: "\n")
            .map { line in
                line
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let capturedRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capturedRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexMatches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.matches(in: text, options: [], range: range)
    }

    private func handleCalculationFlow(input: String, wrapperPrefix: String? = nil) -> Bool {
        let normalized = input.lowercased()

        if isCancelCalculationCommand(normalized) {
            guard calcSession != nil else { return false }
            calcSession = nil
            appendAssistantText("Расчет отменен. Если нужно, начнем заново.")
            return true
        }

        if var session = calcSession {
            let handled = continueCalculation(session: &session, input: normalized)
            if handled {
                calcSession = session
            }
            return handled
        }

        if isCalculationStartIntent(normalized) {
            startCalculationSession(wrapperPrefix: wrapperPrefix)
            return true
        }

        return false
    }

    private func startCalculationSession(wrapperPrefix: String? = nil) {
        calcSession = RecipeCalcSession(flow: nil, step: .selectFlow)
        appendAssistantText(
            composeConversationalReply(
                prefix: wrapperPrefix,
                coreText: """
Я готов считать рецепт прямо в чате )).
Выбери режим:
1) Раствор по концентрации (%) и объему (мл)
2) Разведение из концентрата (C1 -> C2, V)

Напиши `1` или `2`.
"""
            )
        )
    }

    private func composeConversationalReply(prefix: String?, coreText: String) -> String {
        let cleanCore = coreText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix else { return cleanCore }
        let cleanPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrefix.isEmpty else { return cleanCore }
        if cleanCore.isEmpty {
            return cleanPrefix
        }
        if cleanCore.contains("\n") {
            return "\(cleanPrefix)\n\n\(cleanCore)"
        }
        return "\(cleanPrefix) \(cleanCore)"
    }

    private func handleCompendiumInstruction(input: String, wrapperPrefix: String? = nil) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldTryCompendiumLookup(for: trimmed) else { return false }
        pendingCompendiumQuery = nil

        isSearching = true
        responseTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }

            do {
                let hits = try await Task.detached(priority: .userInitiated) {
                    try await CompendiumSQLiteService.shared.searchFTS(trimmed, limit: 5)
                }.value

                if Task.isCancelled { return }
                guard !hits.isEmpty else {
                    await MainActor.run {
                        isSearching = false
                        appendAssistantText(
                            composeConversationalReply(
                                prefix: wrapperPrefix,
                                coreText: compendiumMissPrompt(for: trimmed)
                            )
                        )
                        responseTask = nil
                    }
                    return
                }

                if let exact = bestExactCompendiumHit(for: trimmed, hits: hits) {
                    try await sendCompendiumDetails(
                        for: exact.id,
                        wrapperPrefix: wrapperPrefix,
                        userQuery: trimmed
                    )
                    return
                }

                if hits.count > 1 {
                    await MainActor.run {
                        pendingCompendiumQuery = trimmed
                        isSearching = false
                        let topHits = Array(hits.prefix(5))
                        let variants = topHits.map { hit in
                            compendiumActionTitle(for: hit)
                        }.joined(separator: "\n")

                        let base = """
Я нашёл несколько вариантов в компендиуме )) Уточни, какой именно нужен:
\(variants)
"""
                        appendAssistantMessage(
                            composeConversationalReply(prefix: wrapperPrefix, coreText: base),
                            hits: [],
                            actions: topHits.map { hit in
                                ReferenceAssistantAction(
                                    title: compendiumActionTitle(for: hit),
                                    kind: .compendiumSelection(id: hit.id)
                                )
                            }
                        )
                        responseTask = nil
                    }
                    return
                }

                if let only = hits.first {
                    try await sendCompendiumDetails(for: only.id, wrapperPrefix: wrapperPrefix, userQuery: trimmed)
                    return
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isSearching = false
                    appendAssistantText(
                        composeConversationalReply(
                            prefix: wrapperPrefix,
                            coreText: "Я не смог открыть компендиум: \(error.localizedDescription). Повторим запрос ))?"
                        )
                    )
                    responseTask = nil
                }
            }
        }
        return true
    }

    private func sendCompendiumDetails(for id: String, wrapperPrefix: String?, userQuery: String?) async throws {
        let loaded = try await Task.detached(priority: .userInitiated) {
            try await CompendiumSQLiteService.shared.fetchItem(id: id)
        }.value

        guard let item = loaded else {
            await MainActor.run {
                isSearching = false
                appendAssistantText(
                    composeConversationalReply(
                        prefix: wrapperPrefix,
                        coreText: "Я не нашёл инструкцию по выбранному препарату. Давай проверим название или возьмём другой вариант из списка ))"
                    )
                )
                pendingCompendiumQuery = nil
                responseTask = nil
            }
            return
        }

        if let userQuery,
           let section = requestedCompendiumSection(for: userQuery) {
            let text = renderCompendiumSection(item: item, section: section, query: userQuery)
            await MainActor.run {
                isSearching = false
                appendAssistantText(
                    composeConversationalReply(prefix: wrapperPrefix, coreText: text)
                )
                pendingCompendiumQuery = nil
                responseTask = nil
            }
            return
        }

        let compendiumLLMReply: String?
        if let userQuery, !userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            compendiumLLMReply = await smallTalkService.replyWithCompendium(
                userInput: userQuery,
                item: item
            )
        } else {
            compendiumLLMReply = nil
        }
        let text = compendiumLLMReply ?? renderCompendiumInstruction(for: item)
        await MainActor.run {
            isSearching = false
            appendAssistantText(
                composeConversationalReply(prefix: wrapperPrefix, coreText: text)
            )
            pendingCompendiumQuery = nil
            responseTask = nil
        }
    }

    private func compendiumMissPrompt(for query: String) -> String {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = cleanQuery.isEmpty ? "препарат" : "«\(cleanQuery)»"
        let variants = [
            "По \(topic) я пока не вижу точного совпадения в компендиуме. Дай МНН/торговое название + форму + концентрацию ))",
            "По запросу \(topic) совпадений мало или нет. Уточни, пожалуйста, МНН и лекарственную форму ))",
            "Сейчас по \(topic) в компендиуме пусто. Давай так: название препарата, форма и дозировка — и я добью поиск ))"
        ]
        let index = Int.random(in: 0..<variants.count)
        return variants[index]
    }

    private func shouldTryCompendiumLookup(for input: String) -> Bool {
        guard !input.isEmpty else { return false }
        let normalized = input.lowercased()
        if isPrescriptionInputCandidate(input) { return false }
        if isCalculationStartIntent(normalized) { return false }

        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return false }
        if isCasualDialog(tokens: tokens, normalized: normalized) { return false }

        // Не уводим в компендиум общие вопросы по рецептуре/технологии/навигации.
        let genericAssistantRoots: [String] = [
            "рецепт", "пропи", "технолог", "ппк", "расчет", "расч", "сдел",
            "созда", "конструкт", "бюрет", "фильтр", "вод", "ad", "форум", "вики"
        ]
        if tokens.contains(where: { token in
            genericAssistantRoots.contains(where: { token.hasPrefix($0) })
        }) {
            return false
        }

        let hasDrugMarker = compendiumIntentMarkers.contains { normalized.contains($0) }
        if hasDrugMarker { return true }

        if input.contains("?") {
            return looksLikeDrugLookupCandidate(tokens: tokens, normalized: normalized)
        }

        return looksLikeDrugLookupCandidate(tokens: tokens, normalized: normalized)
    }

    private func shouldForceCasualDialog(input: String, taskIntent: ConversationTaskIntent) -> Bool {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isPrescriptionInputCandidate(input) else { return false }
        if isCalculationStartIntent(input.lowercased()) { return false }
        if taskIntent == .navigation { return false }

        let normalized = input
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        if isNavigationRouteQuestion(normalizedQuery: normalized) { return false }

        // "Что умеешь?" лучше отдавать в app-hint маршрутизатор, а не в casual-чат.
        let appCapabilitiesMarkers = [
            "что ты умеешь", "что умеет приложение", "возможности приложения", "функции приложения", "что может uran"
        ]
        if appCapabilitiesMarkers.contains(where: { normalized.contains($0) }) {
            return false
        }

        let openDialogMarkers = [
            "кто ты", "кто ты такой", "что ты такое", "как тебя зовут", "представься",
            "чем занимаешься", "ты тут", "ты здесь", "ты живой", "ты бот",
            "какая погода", "какая сейчас погода", "погода сегодня", "погода",
            "который час", "сколько времени", "сколько сейчас времени"
        ]
        if openDialogMarkers.contains(where: { normalized.contains($0) }) {
            return true
        }

        let reactionMarkers = [
            "круто", "класс", "супер", "огонь", "прикольно", "топ",
            "то что нужно", "именно то", "отлично", "нормально", "пасиб", "спасибо"
        ]
        if reactionMarkers.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return false }
        if lastCasualTopic != nil {
            if normalized == "где" || normalized == "где?" || normalized.hasPrefix("так где") {
                return true
            }
        }
        if isCasualDialog(tokens: tokens, normalized: normalized) { return true }

        let domainRoots = [
            "рецеп", "пропи", "технол", "компенди", "препарат", "лекар",
            "доз", "концент", "раствор", "ингреди", "бюрет", "ппк",
            "стерил", "фильтр", "капл", "маз", "насто", "эмуль", "суспенз"
        ]
        let hasDomainSignal = tokens.contains { token in
            domainRoots.contains { token.hasPrefix($0) }
        }
        if hasDomainSignal { return false }

        let isShortQuestion = input.contains("?") && tokens.count <= 6
        return isShortQuestion
    }

    private func fallbackForCasualDialog(input: String, defaultResponse: String) -> String {
        let normalized = input
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        if lastCasualTopic == .weather {
            if normalized == "где" || normalized == "где?" || normalized.hasPrefix("так где") || normalized.contains("где провер") {
                return "Я бы выглянул в окно, но я же Uran в телефоне )) Открой «Погода» или Windy."
            }
        }
        if lastCasualTopic == .time {
            if normalized == "где" || normalized == "где?" || normalized.contains("где посмотреть") {
                return "Я без наручных часов )) Смотри статус-бар или виджет «Часы»."
            }
        }

        if normalized.contains("кто ты") || normalized.contains("кто ты такой") || normalized.contains("ты бот") {
            lastCasualTopic = .identity
            return "Я — Uran )) Помогаю с рецептурой, аптехнологией и разбором сложных случаев."
        }
        if normalized.contains("как тебя зовут") || normalized.contains("представься") {
            lastCasualTopic = .identity
            return "Я — Uran )) Можно просто: «Uran, помоги»."
        }
        if normalized.contains("какая погода") || normalized.contains("погода") {
            lastCasualTopic = .weather
            return "Погоду в реальном времени я не вижу, но подскажу путь )) Открой «Погода» или Gismeteo."
        }
        if normalized.contains("который час") || normalized.contains("сколько времени") {
            lastCasualTopic = .time
            return "Точное время в чате не вижу )) Проверь статус-бар, и идём дальше."
        }
        if normalized.contains("ты тут") || normalized.contains("ты здесь") {
            return "Да, я тут и в рабочем режиме ))"
        }
        if normalized.contains("круто")
            || normalized.contains("супер")
            || normalized.contains("класс")
            || normalized.contains("то что нужно")
            || normalized.contains("прикольно")
            || normalized.contains("отлично") {
            return "Огонь )) Тогда продолжаем: хочешь диалог или сразу задача?"
        }
        if normalized.contains("спасибо") || normalized.contains("пасиб") || normalized.contains("благодар") {
            return "Всегда пожалуйста )) Если нужно, продолжаем."
        }
        return defaultResponse
    }

    private func isCasualDialog(tokens: [String], normalized: String) -> Bool {
        if normalized.contains("как дела") || normalized.contains("че как") || normalized.contains("че нового") {
            return true
        }

        let greetingRoots = [
            "привет", "здрав", "здоров", "здаров", "хай", "салют", "добр", "hello", "hi", "ку"
        ]
        let politeRoots = [
            "спасиб", "благодар", "понят", "понял", "ясн", "норм", "ок", "ага"
        ]
        let laughterRoots = [
            "ахах", "аха", "хаха", "лол", "гы", "ржу", "ор", "кек"
        ]
        let reactionRoots = [
            "крут", "класс", "супер", "огонь", "прикол", "топ", "отлич", "спасиб", "благодар"
        ]

        let hasGreeting = tokens.contains { token in greetingRoots.contains { token.hasPrefix($0) } }
        let hasPolite = tokens.contains { token in politeRoots.contains { token.hasPrefix($0) } }
        let hasLaughter = tokens.contains { token in laughterRoots.contains { token.hasPrefix($0) } }
        let hasReaction = tokens.contains { token in reactionRoots.contains { token.hasPrefix($0) } }

        if hasGreeting && tokens.count <= 4 {
            return true
        }
        if hasPolite && tokens.count <= 3 {
            return true
        }
        if hasLaughter && tokens.count <= 8 {
            return true
        }
        if hasReaction && tokens.count <= 8 {
            return true
        }
        return false
    }

    private func looksLikeDrugLookupCandidate(tokens: [String], normalized: String) -> Bool {
        guard !tokens.isEmpty else { return false }
        if isCasualDialog(tokens: tokens, normalized: normalized) { return false }

        let lookupVerbRoots = ["найд", "ищ", "поиск", "покаж", "инструкц", "доз", "побоч", "взаимодейств", "противопоказ", "показан"]
        let serviceWords: Set<String> = [
            "мне", "моя", "мой", "мои", "это", "этот", "эта", "про", "по", "для", "пожалуйста", "нужно", "надо"
        ]
        let intentWords = [
            "доза", "дозы", "дозировка", "инструкция", "показания", "противопоказания",
            "побочки", "побочные", "взаимодействия", "применение", "форма", "концентрация"
        ]

        let hasLookupVerb = tokens.contains { token in lookupVerbRoots.contains { token.hasPrefix($0) } }
        let candidateTokens = tokens.filter { token in
            !serviceWords.contains(token) && !intentWords.contains(token)
        }
        let hasDrugLikeToken = candidateTokens.contains { token in
            token.count >= 3 && token.range(of: #"^\p{L}+$"#, options: .regularExpression) != nil
        }

        if hasLookupVerb && hasDrugLikeToken {
            return true
        }
        if candidateTokens.count == 1 && hasDrugLikeToken {
            return true
        }
        return false
    }

    private func bestExactCompendiumHit(for query: String, hits: [CompendiumHit]) -> CompendiumHit? {
        let q = normalizedCompendiumText(query)
        guard !q.isEmpty else { return nil }
        return hits.first { hit in
            normalizedCompendiumText(hit.id) == q
                || normalizedCompendiumText(hit.brandName ?? "") == q
                || normalizedCompendiumText(hit.inn ?? "") == q
        }
    }

    private func normalizedCompendiumText(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestedCompendiumSection(for query: String) -> CompendiumSection? {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        let checks: [(CompendiumSection, [String])] = [
            (.composition, ["состав", "ингредиент", "composition", "что входит"]),
            (.dosageForm, ["форма", "лекарственная форма", "dosage form"]),
            (.pharmacologicalProperties, ["фармаколог", "механизм", "pharmacological"]),
            (.indications, ["показани", "от чего", "для чего", "indications"]),
            (.dosageAdministration, ["доза", "дозиров", "как принимать", "способ применения", "применение", "dosage"]),
            (.contraindications, ["противопоказ", "contraindications"]),
            (.sideEffects, ["побоч", "нежелател", "side effects"]),
            (.interactions, ["взаимодейств", "совместим", "interactions"]),
            (.overdose, ["передоз", "overdose"]),
            (.storageConditions, ["хранен", "storage"])
        ]

        for (section, markers) in checks {
            if markers.contains(where: { normalized.contains($0) }) {
                return section
            }
        }
        return nil
    }

    private func renderCompendiumSection(item: CompendiumItemDetails, section: CompendiumSection, query: String? = nil) -> String {
        let title: String = {
            let brand = (item.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return brand.isEmpty ? item.id : brand
        }()

        if section == .dosageAdministration,
           let query,
           let focused = focusedDosageSectionText(from: item.dosageAdministration, query: query) {
            return "Препарат: \(title)\n\(section.rawValue):\n\(focused)"
        }

        let rawValue: String? = {
            switch section {
            case .composition:
                return item.composition
            case .dosageForm:
                return item.dosageForm
            case .pharmacologicalProperties:
                return item.pharmacologicalProperties
            case .indications:
                return item.indications
            case .dosageAdministration:
                return item.dosageAdministration
            case .contraindications:
                return item.contraindications
            case .sideEffects:
                return item.sideEffects
            case .interactions:
                return item.interactions
            case .overdose:
                return item.overdose
            case .storageConditions:
                return item.storageConditions
            }
        }()

        let text = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "Препарат: \(title)\n\(section.rawValue):\nВ этом блоке данных нет."
        }
        return "Препарат: \(title)\n\(section.rawValue):\n\(text)"
    }

    private func focusedDosageSectionText(from raw: String?, query: String) -> String? {
        let source = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        let audience = requestedCompendiumAudience(for: query)
        guard let audience else { return nil }

        let fragments = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: CharacterSet(charactersIn: ";\n."))
            .map { fragment in
                fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard !fragments.isEmpty else { return nil }

        let matched: [String] = fragments.filter { fragment in
            let normalized = fragment
                .lowercased()
                .replacingOccurrences(of: "ё", with: "е")
            switch audience {
            case .pediatric:
                return normalized.contains("дет")
                    || normalized.contains("ребен")
                    || normalized.contains("грудн")
                    || normalized.contains("новорожден")
                    || normalized.contains("младен")
                    || normalized.contains("подрост")
            case .adult:
                return normalized.contains("взросл")
                    || normalized.contains("старше 14")
                    || normalized.contains("старше 18")
            }
        }

        let selected = Array(matched.prefix(8))
        guard !selected.isEmpty else { return nil }
        return selected.map { "• \($0)" }.joined(separator: "\n")
    }

    private func requestedCompendiumAudience(for query: String) -> CompendiumAudience? {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        if normalized.contains("дет")
            || normalized.contains("ребен")
            || normalized.contains("педиатр")
            || normalized.contains("младен")
            || normalized.contains("грудн") {
            return .pediatric
        }
        if normalized.contains("взросл") || normalized.contains("для взрослых") {
            return .adult
        }
        return nil
    }

    private func renderCompendiumInstruction(for item: CompendiumItemDetails) -> String {
        let title = {
            let brand = (item.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !brand.isEmpty { return brand }
            return item.id
        }()

        var lines: [String] = []
        lines.append("Инструкция по препарату: \(title)")

        let inn = (item.inn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inn.isEmpty {
            lines.append("МНН: \(inn)")
        }
        let atc = (item.atcCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !atc.isEmpty {
            lines.append("ATC: \(atc)")
        }
        let dosageForm = (item.dosageForm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !dosageForm.isEmpty {
            lines.append("Dosage Form: \(dosageForm)")
        }

        func appendSection(_ title: String, _ text: String?) {
            let clean = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            lines.append("")
            lines.append("\(title):")
            lines.append(clean)
        }

        appendSection("Состав", item.composition)
        appendSection("Показания", item.indications)
        appendSection("Способ применения", item.dosageAdministration)
        appendSection("Противопоказания", item.contraindications)
        appendSection("Побочные эффекты", item.sideEffects)
        appendSection("Взаимодействия", item.interactions)
        appendSection("Передозировка", item.overdose)
        appendSection("Условия хранения", item.storageConditions)

        return lines.joined(separator: "\n")
    }

    private func compendiumActionTitle(for hit: CompendiumHit) -> String {
        let brand = (hit.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inn = (hit.inn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !brand.isEmpty, !inn.isEmpty {
            return "\(brand) (\(inn))"
        }
        return brand.isEmpty ? hit.id : brand
    }

    private let compendiumIntentMarkers: [String] = [
        "инструкция",
        "препарат",
        "лекарство",
        "доза",
        "показания",
        "противопоказ",
        "дозиров",
        "побоч",
        "взаимодейств"
    ]

    private func continueCalculation(session: inout RecipeCalcSession, input: String) -> Bool {
        switch session.step {
        case .selectFlow:
            if input.contains("1") || input.contains("раствор") || input.contains("%") {
                session.flow = .solutionPercent
                session.step = .solutionConcentration
                appendAssistantText("Введи концентрацию раствора в %, например: `5`")
                return true
            }
            if input.contains("2") || input.contains("развед") || input.contains("концентрат") {
                session.flow = .dilution
                session.step = .dilutionStockConcentration
                appendAssistantText("Введи исходную концентрацию C1 (%), например: `20`")
                return true
            }

            appendAssistantText("Не понял выбор. Напиши `1` (раствор) или `2` (разведение).")
            return true

        case .solutionConcentration:
            guard let concentration = parseFirstNumber(from: input), concentration > 0 else {
                appendAssistantText("Нужна корректная концентрация > 0. Пример: `2.5`")
                return true
            }
            session.concentrationPercent = concentration
            session.step = .solutionVolume
            appendAssistantText("Теперь введи конечный объем в мл, например: `100`")
            return true

        case .solutionVolume:
            guard let volume = parseFirstNumber(from: input), volume > 0 else {
                appendAssistantText("Нужен объем > 0 мл. Пример: `200`")
                return true
            }
            session.volumeMl = volume

            let concentration = session.concentrationPercent ?? 0
            let massG = concentration * volume / 100.0
            let result = """
Расчет готов.

Формула: m = C × V / 100
C = \(formatDouble(concentration))%
V = \(formatDouble(volume)) мл

Нужно вещества: \(formatDouble(massG)) г
Растворитель: очищенная вода ad \(formatDouble(volume)) мл

Если хочешь, следующим сообщением могу сразу посчитать разведение C1 -> C2.
"""
            calcSession = nil
            appendAssistantText(result)
            return true

        case .dilutionStockConcentration:
            guard let stock = parseFirstNumber(from: input), stock > 0 else {
                appendAssistantText("Нужна исходная концентрация C1 > 0. Пример: `96`")
                return true
            }
            session.stockPercent = stock
            session.step = .dilutionTargetConcentration
            appendAssistantText("Введи целевую концентрацию C2 (%), например: `70`")
            return true

        case .dilutionTargetConcentration:
            guard let target = parseFirstNumber(from: input), target > 0 else {
                appendAssistantText("Нужна целевая концентрация C2 > 0. Пример: `40`")
                return true
            }
            let stock = session.stockPercent ?? 0
            guard target < stock else {
                appendAssistantText("C2 должна быть меньше C1. Сейчас C1 = \(formatDouble(stock))%.")
                return true
            }
            session.targetPercent = target
            session.step = .dilutionTargetVolume
            appendAssistantText("Введи конечный объем V (мл), например: `100`")
            return true

        case .dilutionTargetVolume:
            guard let targetVolume = parseFirstNumber(from: input), targetVolume > 0 else {
                appendAssistantText("Нужен конечный объем > 0 мл. Пример: `50`")
                return true
            }

            session.targetVolumeMl = targetVolume
            let c1 = session.stockPercent ?? 0
            let c2 = session.targetPercent ?? 0
            let v2 = session.targetVolumeMl ?? 0
            let v1 = (c2 * v2) / c1
            let water = max(v2 - v1, 0)

            let result = """
Расчет разведения готов.

Формула: C1 × V1 = C2 × V2
C1 = \(formatDouble(c1))%
C2 = \(formatDouble(c2))%
V2 = \(formatDouble(v2)) мл

Нужно концентрата (V1): \(formatDouble(v1)) мл
Добавить воды: \(formatDouble(water)) мл
"""
            calcSession = nil
            appendAssistantText(result)
            return true
        }
    }

    private func appendAssistantText(_ text: String) {
        appendAssistantMessage(text, hits: [], actions: [])
    }

    private func appendAssistantMessage(_ text: String, hits: [ReferenceKnowledgeHit], actions: [ReferenceAssistantAction]) {
        withAnimation(.easeInOut(duration: 0.24)) {
            messages.append(
                ReferenceAssistantMessage(
                    role: .assistant,
                    text: text,
                    hits: hits,
                    actions: actions
                )
            )
        }
    }

    private func isCalculationStartIntent(_ text: String) -> Bool {
        if text.contains("рассч") && text.contains("рецепт") { return true }
        if text.contains("посч") && text.contains("рецепт") { return true }
        if text.contains("расчет") && text.contains("раствор") { return true }
        if text.contains("рассч") && text.contains("развед") { return true }
        return false
    }

    private func isCancelCalculationCommand(_ text: String) -> Bool {
        text == "стоп" || text == "отмена" || text == "отменить" || text == "cancel" || text == "сброс"
    }

    private func parseFirstNumber(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"-?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(normalized[range])
    }

    private func formatDouble(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        if (value * 10).rounded(.towardZero) == value * 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}

private actor LocalSmallTalkLLMService {
    static let shared = LocalSmallTalkLLMService()

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let top_p: Double
        let max_tokens: Int
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct ChoiceMessage: Decodable {
                let content: String?
            }

            let message: ChoiceMessage?
            let text: String?
        }

        let choices: [Choice]?
    }

    private let session: URLSession
    private var unavailableUntil: Date?
#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private var foundationSession: LanguageModelSession?
#endif

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.2
        config.timeoutIntervalForResource = 3.0
        self.session = URLSession(configuration: config)
    }

    func reset() {
        unavailableUntil = nil
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            foundationSession = nil
        }
#endif
    }

    func reply(userInput: String, history: [ReferenceAssistantMessage]) async -> String? {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let unavailableUntil, unavailableUntil > Date() {
            return nil
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let onDevice = await replyWithFoundationModel(userInput: userInput) {
            return onDevice
        }
#endif

        let messages = buildMessages(userInput: userInput, history: history)
        for endpoint in endpoints() {
            for model in preferredModelNames(for: endpoint) {
                let wallStart = Date()
                let cpuStart = appCPUTimeSeconds()
                let body = ChatRequest(
                    model: model,
                    messages: messages,
                    temperature: 0.35,
                    top_p: 0.9,
                    max_tokens: 56,
                    stream: false
                )
                guard let encoded = try? JSONEncoder().encode(body) else { continue }

                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.httpBody = encoded
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continue
                    }
                    if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
                       let raw = decoded.choices?.first?.message?.content ?? decoded.choices?.first?.text,
                       let clean = sanitize(raw) {
                        logPerf(label: "HTTP LLM [\(model)]", wallStart: wallStart, cpuStart: cpuStart)
                        unavailableUntil = nil
                        return clean
                    }
                } catch {
                    continue
                }
            }
        }

        unavailableUntil = Date().addingTimeInterval(15)
        return nil
    }

    func replyWithCompendium(userInput: String, item: CompendiumItemDetails) async -> String? {
        let question = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return nil }
        let grounding = buildCompendiumGrounding(item: item)
        guard !grounding.isEmpty else { return nil }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let onDevice = await replyWithFoundationModelGrounded(userInput: question, grounding: grounding) {
            return onDevice
        }
#endif

        let messages = buildCompendiumMessages(userInput: question, grounding: grounding)
        for endpoint in endpoints() {
            for model in preferredModelNames(for: endpoint) {
                let wallStart = Date()
                let cpuStart = appCPUTimeSeconds()
                let body = ChatRequest(
                    model: model,
                    messages: messages,
                    temperature: 0.2,
                    top_p: 0.9,
                    max_tokens: 180,
                    stream: false
                )
                guard let encoded = try? JSONEncoder().encode(body) else { continue }

                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.httpBody = encoded
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continue
                    }
                    if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
                       let raw = decoded.choices?.first?.message?.content ?? decoded.choices?.first?.text,
                       let clean = sanitizeGrounded(raw) {
                        logPerf(label: "Compendium LLM [\(model)]", wallStart: wallStart, cpuStart: cpuStart)
                        return clean
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    func replyWithKnowledge(userInput: String, hits: [ReferenceKnowledgeHit]) async -> String? {
        let question = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return nil }
        guard !hits.isEmpty else { return nil }
        let grounding = buildKnowledgeGrounding(hits: hits)
        guard !grounding.isEmpty else { return nil }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let onDevice = await replyWithFoundationModelKnowledge(userInput: question, grounding: grounding) {
            return onDevice
        }
#endif

        let messages = buildKnowledgeMessages(userInput: question, grounding: grounding)
        for endpoint in endpoints() {
            for model in preferredModelNames(for: endpoint) {
                let wallStart = Date()
                let cpuStart = appCPUTimeSeconds()
                let body = ChatRequest(
                    model: model,
                    messages: messages,
                    temperature: 0.22,
                    top_p: 0.9,
                    max_tokens: 220,
                    stream: false
                )
                guard let encoded = try? JSONEncoder().encode(body) else { continue }

                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.httpBody = encoded
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continue
                    }
                    if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
                       let raw = decoded.choices?.first?.message?.content ?? decoded.choices?.first?.text,
                       let clean = sanitizeKnowledge(raw) {
                        logPerf(label: "Knowledge LLM [\(model)]", wallStart: wallStart, cpuStart: cpuStart)
                        return clean
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func replyWithFoundationModel(userInput: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        if foundationSession == nil {
            foundationSession = LanguageModelSession(
                model: model,
                instructions: """
Ты — Uran, встроенный ассистент приложения.
Говори от первого лица: «Я ...».
Отвечай коротко и естественно: 1 короткая фраза, максимум 16 слов.
Если вопрос явно оффтопный, можно добавить лёгкую шутку и «))».
"""
            )
        }

        guard let foundationSession else { return nil }
        let wallStart = Date()
        let cpuStart = appCPUTimeSeconds()

        do {
            let response = try await foundationSession.respond(to: userInput)
            guard let clean = sanitize(response.content) else { return nil }
            logPerf(label: "FoundationModels", wallStart: wallStart, cpuStart: cpuStart)
            return clean
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func replyWithFoundationModelGrounded(userInput: String, grounding: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
Ты — Uran, встроенный ассистент приложения.
Говори строго от первого лица.
Отвечай только по переданному контексту компендиума.
Если данных в контексте нет, скажи это и попроси уточнить препарат/форму с дружелюбным «))».
Пиши естественно, кратко: 2-4 предложения без воды.
Не выдумывай факты, дозы и противопоказания.
"""
        )
        let prompt = """
Вопрос пользователя:
\(userInput)

Контекст из компендиума:
\(grounding)
"""
        let wallStart = Date()
        let cpuStart = appCPUTimeSeconds()

        do {
            let response = try await session.respond(to: prompt)
            guard let clean = sanitizeGrounded(response.content) else { return nil }
            logPerf(label: "FoundationModels Compendium", wallStart: wallStart, cpuStart: cpuStart)
            return clean
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func replyWithFoundationModelKnowledge(userInput: String, grounding: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
Ты — Uran, встроенный ассистент приложения.
Говори от первого лица.
Отвечай только по контексту книги/базы ниже.
Если прямого ответа нет, попроси уточнение по сути вопроса и добавь «))».
Формат: 2-4 коротких предложения, без выдуманных фактов.
"""
        )
        let prompt = """
Вопрос пользователя:
\(userInput)

Контекст книги/базы:
\(grounding)
"""
        let wallStart = Date()
        let cpuStart = appCPUTimeSeconds()

        do {
            let response = try await session.respond(to: prompt)
            guard let clean = sanitizeKnowledge(response.content) else { return nil }
            logPerf(label: "FoundationModels Knowledge", wallStart: wallStart, cpuStart: cpuStart)
            return clean
        } catch {
            return nil
        }
    }
#endif

    private func endpoints() -> [URL] {
        var urls: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: "uran.localLLM.endpoint"),
           let customURL = URL(string: custom.trimmingCharacters(in: .whitespacesAndNewlines)) {
            urls.append(customURL)
        }
        if let localhost = URL(string: "http://127.0.0.1:8080/v1/chat/completions") {
            urls.append(localhost)
        }
        if let localhostAlt = URL(string: "http://localhost:8080/v1/chat/completions") {
            urls.append(localhostAlt)
        }
        if let ollamaLocal = URL(string: "http://127.0.0.1:11434/v1/chat/completions") {
            urls.append(ollamaLocal)
        }
        if let ollamaAlt = URL(string: "http://localhost:11434/v1/chat/completions") {
            urls.append(ollamaAlt)
        }
        return urls
    }

    private func preferredModelNames(for endpoint: URL) -> [String] {
        if let custom = UserDefaults.standard.string(forKey: "uran.localLLM.model")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return [custom]
        }
        if endpoint.port == 11434 {
            return ["uran-chat:1b", "llama3.2:1b"]
        }
        return ["local-model"]
    }

    private func buildMessages(userInput: String, history: [ReferenceAssistantMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = [
            ChatMessage(
                role: "system",
                content: """
Ты — Uran, встроенный ассистент приложения.
Говори от первого лица.
Отвечай естественно и просто: 1 короткая фраза, максимум 16 слов, без длинных рассуждений.
Если пользователь просто здоровается/шутит — поддержи разговор по-человечески, можно с «))».
Не начинай философствовать, не перечисляй абстрактные категории, не пиши канцеляритом.
Если вопрос про рецепт или технологию — мягко попроси прислать состав/пропись.
"""
            )
        ]

        let recent = history.suffix(6)
        for item in recent {
            let role = item.role == .user ? "user" : "assistant"
            let content = clip(item.text, limit: 280)
            guard !content.isEmpty else { continue }
            result.append(ChatMessage(role: role, content: content))
        }

        if result.last?.role != "user" {
            result.append(ChatMessage(role: "user", content: clip(userInput, limit: 280)))
        }
        return result
    }

    private func buildCompendiumMessages(userInput: String, grounding: String) -> [ChatMessage] {
        [
            ChatMessage(
                role: "system",
                content: """
Ты — Uran, встроенный ассистент приложения.
Говори от первого лица.
Отвечай только по контексту компендиума ниже.
Если в контексте нет ответа, скажи это и попроси уточнить по препарату/форме с «))».
Формат: 2-4 коротких предложения, просто и по-человечески.
Не выдумывай факты.
"""
            ),
            ChatMessage(
                role: "user",
                content: """
Вопрос: \(clip(userInput, limit: 260))

Контекст компендиума:
\(grounding)
"""
            )
        ]
    }

    private func buildKnowledgeMessages(userInput: String, grounding: String) -> [ChatMessage] {
        [
            ChatMessage(
                role: "system",
                content: """
Ты — Uran, встроенный ассистент приложения.
Говори от первого лица.
Отвечай только по контексту книги/базы ниже.
Если данных недостаточно, попроси уточнить вопрос (форма/концентрация/операция) и добавь «))».
Формат: 2-4 коротких предложения. Без выдуманных фактов.
"""
            ),
            ChatMessage(
                role: "user",
                content: """
Вопрос: \(clip(userInput, limit: 260))

Контекст книги/базы:
\(grounding)
"""
            )
        ]
    }

    private func buildKnowledgeGrounding(hits: [ReferenceKnowledgeHit]) -> String {
        let top = Array(hits.prefix(4))
        guard !top.isEmpty else { return "" }
        var lines: [String] = []
        for (idx, hit) in top.enumerated() {
            lines.append("Фрагмент \(idx + 1): \(clip(hit.title, limit: 120))")
            lines.append(clip(hit.snippet, limit: 520))
            if !hit.tags.isEmpty {
                lines.append("Теги: \(clip(hit.tags.joined(separator: ", "), limit: 140))")
            }
            if let pageFrom = hit.pageFrom {
                if let pageTo = hit.pageTo, pageTo != pageFrom {
                    lines.append("Страницы: \(pageFrom)-\(pageTo)")
                } else {
                    lines.append("Страница: \(pageFrom)")
                }
            }
        }
        return clip(lines.joined(separator: "\n"), limit: 3000)
    }

    private func buildCompendiumGrounding(item: CompendiumItemDetails) -> String {
        let title = (item.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? item.id : title
        var lines: [String] = ["Препарат: \(name)"]

        let inn = (item.inn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inn.isEmpty { lines.append("МНН: \(clip(inn, limit: 180))") }

        let atc = (item.atcCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !atc.isEmpty { lines.append("ATC: \(clip(atc, limit: 80))") }
        let dosageForm = (item.dosageForm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !dosageForm.isEmpty { lines.append("Dosage Form: \(clip(dosageForm, limit: 200))") }

        func add(_ title: String, _ text: String?, limit: Int = 520) {
            let clean = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            lines.append("\(title): \(clip(clean, limit: limit))")
        }

        add("Состав", item.composition, limit: 420)
        add("Показания", item.indications)
        add("Способ применения", item.dosageAdministration)
        add("Противопоказания", item.contraindications)
        add("Побочные эффекты", item.sideEffects)
        add("Взаимодействия", item.interactions)
        add("Передозировка", item.overdose, limit: 380)
        add("Условия хранения", item.storageConditions, limit: 260)

        return clip(lines.joined(separator: "\n"), limit: 2600)
    }

    private func sanitize(_ source: String) -> String? {
        let cleaned = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        let bannedFragments = [
            "в то время как", "рассматривает все аспекты", "социальные взаимодействия",
            "мыслительный процесс", "как искусственный интеллект", "в целом",
            "позвольте", "итак,"
        ]
        if bannedFragments.contains(where: { lowered.contains($0) }) {
            return nil
        }

        let punctuationCount = cleaned.filter { ".!?".contains($0) }.count
        if punctuationCount > 2 || cleaned.count > 180 {
            return nil
        }

        return clip(cleaned, limit: 140)
    }

    private func sanitizeGrounded(_ source: String) -> String? {
        let cleaned = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        if lowered.contains("как искусственный интеллект")
            || lowered.contains("я не врач")
            || lowered.contains("не является медицинской консультацией") {
            return nil
        }
        return clip(cleaned, limit: 420)
    }

    private func sanitizeKnowledge(_ source: String) -> String? {
        let cleaned = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        if lowered.contains("как искусственный интеллект")
            || lowered.contains("я не врач")
            || lowered.contains("не является медицинской консультацией") {
            return nil
        }
        return clip(cleaned, limit: 520)
    }

    private func clip(_ text: String, limit: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit - 1)) + "…"
    }

    private func appCPUTimeSeconds() -> TimeInterval? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
        return user + system
    }

    private func logPerf(label: String, wallStart: Date, cpuStart: TimeInterval?) {
        let wall = Date().timeIntervalSince(wallStart)
        guard wall > 0 else { return }
        guard let cpuStart, let cpuEnd = appCPUTimeSeconds() else {
            NSLog("%@: wall %.3fs (cpu unavailable)", label, wall)
            return
        }
        let cpu = max(cpuEnd - cpuStart, 0)
        let cpuPercent = (cpu / wall) * 100
        NSLog("%@: wall %.3fs cpu %.3fs (~%.1f%%)", label, wall, cpu, cpuPercent)
    }
}

private actor ReferenceKnowledgeSearchService {
    static let shared = ReferenceKnowledgeSearchService()

    private var chunks: [ReferenceKnowledgeChunk] = []
    private var faqEntries: [ReferenceFAQEntry] = []
    private var nlpAssets: ReferenceNLPAssets = .empty
    private var didAttemptLoad = false
    private var loadError: String?

    func answer(for query: String, limit: Int) async -> ReferenceAssistantResponse {
        await ensureLoaded()

        let normalizedQuery = normalize(query)
        let queryTokens = tokenized(query)
        guard !queryTokens.isEmpty else {
            return .init(
                answerText: contextualClarification(
                    for: query,
                    fallbackTopic: "запрос слишком короткий"
                ),
                hits: []
            )
        }
        let normalizedQueryVariants = expandedQueryVariants(from: normalizedQuery)
        let searchTokens = expandedQueryTokens(
            originalTokens: queryTokens,
            normalizedQueryVariants: normalizedQueryVariants
        )

        if let loadError, chunks.isEmpty {
            return .init(answerText: "Я не смог открыть локальный справочник: \(loadError). Повтори запрос чуть позже ))", hits: [])
        }

        if let appHint = bestAppHint(normalizedQuery: normalizedQuery, queryTokens: queryTokens) {
            return .init(
                answerText: appHint.answer,
                hits: [appHintHit(from: appHint)]
            )
        }

        if chunks.isEmpty {
            return .init(
                answerText: contextualClarification(
                    for: query,
                    fallbackTopic: "книга технологий ещё не загружена в справочник"
                ),
                hits: []
            )
        }

        let ranked = chunks
            .compactMap { chunk -> (chunk: ReferenceKnowledgeChunk, score: Int)? in
                let score = relevanceScore(for: chunk, normalizedQuery: normalizedQuery, tokens: searchTokens)
                return score > 0 ? (chunk, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.chunk.pageFrom ?? Int.max < rhs.chunk.pageFrom ?? Int.max
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { pair in
                ReferenceKnowledgeHit(
                    id: pair.chunk.id,
                    title: pair.chunk.title,
                    snippet: makeSnippet(from: pair.chunk.body, for: queryTokens),
                    pageFrom: pair.chunk.pageFrom,
                    pageTo: pair.chunk.pageTo,
                    tags: pair.chunk.tags,
                    docID: pair.chunk.docID
                )
            }

        if ranked.isEmpty {
            return .init(
                answerText: contextualClarification(
                    for: query,
                    fallbackTopic: "прямого совпадения в книге не вижу"
                ),
                hits: []
            )
        }

        let answerText = leadAnswer(from: ranked[0])
        return .init(answerText: answerText, hits: Array(ranked))
    }

    private func ensureLoaded() async {
        if didAttemptLoad { return }
        didAttemptLoad = true

        var primaryErrors: [String] = []

        do {
            chunks = try Self.loadChunks()
        } catch {
            primaryErrors.append(error.localizedDescription)
            chunks = []
        }

        do {
            nlpAssets = try Self.loadNLPAssets()
        } catch {
            nlpAssets = .empty
        }

        if chunks.isEmpty {
            if primaryErrors.isEmpty {
                loadError = "база пуста"
            } else {
                loadError = primaryErrors.joined(separator: " | ")
            }
        }
    }

    private func bestAppHint(
        normalizedQuery: String,
        queryTokens: [String]
    ) -> ReferenceAppHint? {
        var best: (hint: ReferenceAppHint, score: Int)?

        for hint in Self.appHints {
            if hint.id == "app_capabilities" {
                let isCapabilitiesIntent = Self.capabilitiesTriggers.contains { normalizedQuery.contains($0) }
                if !isCapabilitiesIntent {
                    continue
                }
            }

            var score = 0
            for keyword in hint.keywords {
                if normalizedQuery.contains(keyword) {
                    score += 8
                }
                for token in queryTokens where keyword.contains(token) || token.contains(keyword) {
                    score += 3
                }
            }

            if let current = best {
                if score > current.score {
                    best = (hint, score)
                }
            } else if score > 0 {
                best = (hint, score)
            }
        }

        guard let best, best.score >= 10 else { return nil }
        return best.hint
    }

    private func appHintHit(from hint: ReferenceAppHint) -> ReferenceKnowledgeHit {
        ReferenceKnowledgeHit(
            id: "app-\(hint.id)",
            title: "Где в URAN: \(hint.title)",
            snippet: hint.answer,
            pageFrom: nil,
            pageTo: nil,
            tags: ["APP_NAVIGATION"],
            docID: "uran_app_guide"
        )
    }

    private func bestFAQMatch(normalizedQueries: [String], queryTokens: [String]) -> (entry: ReferenceFAQEntry, score: Int)? {
        var best: (entry: ReferenceFAQEntry, score: Int)?

        for entry in faqEntries {
            let score = normalizedQueries.reduce(into: 0) { current, variant in
                current = max(current, faqScore(for: entry, normalizedQuery: variant, queryTokens: queryTokens))
            }
            if score <= 0 { continue }
            if best == nil || score > best!.score {
                best = (entry, score)
            }
        }

        return best
    }

    private func expandedQueryVariants(from normalizedQuery: String) -> [String] {
        var ordered = [normalizedQuery]
        var seen = Set(ordered)

        for (source, aliases) in nlpAssets.phraseAliases {
            guard normalizedQuery.contains(source) else { continue }
            for alias in aliases.prefix(3) {
                let variant = normalizedQuery.replacingOccurrences(of: source, with: alias)
                guard variant.count >= 2, !seen.contains(variant) else { continue }
                seen.insert(variant)
                ordered.append(variant)
            }
        }

        return ordered
    }

    private func expandedQueryTokens(
        originalTokens: [String],
        normalizedQueryVariants: [String]
    ) -> [String] {
        var ordered = originalTokens
        var seen = Set(originalTokens)

        func appendIfNeeded(_ token: String) {
            guard token.count >= 2, !seen.contains(token) else { return }
            seen.insert(token)
            ordered.append(token)
        }

        for token in originalTokens {
            for alias in nlpAssets.tokenAliases[token] ?? [] {
                appendIfNeeded(alias)
            }
        }

        for variant in normalizedQueryVariants {
            let variantTokens = tokenized(variant)
            for token in variantTokens {
                appendIfNeeded(token)
                for alias in nlpAssets.tokenAliases[token] ?? [] {
                    appendIfNeeded(alias)
                }
            }
        }

        return ordered
    }

    private func faqScore(
        for entry: ReferenceFAQEntry,
        normalizedQuery: String,
        queryTokens: [String]
    ) -> Int {
        var score = 0

        if entry.normalizedQuestion == normalizedQuery {
            score += 120
        }
        if entry.normalizedQuestion.contains(normalizedQuery), normalizedQuery.count >= 4 {
            score += 45
        }
        if normalizedQuery.contains(entry.normalizedQuestion), entry.normalizedQuestion.count >= 6 {
            score += 28
        }

        let overlap = queryTokens.reduce(into: 0) { acc, token in
            if entry.tokens.contains(token) {
                acc += 1
            }
        }

        score += overlap * 8

        if !queryTokens.isEmpty {
            let coverage = Double(overlap) / Double(queryTokens.count)
            if coverage >= 0.85 {
                score += 24
            } else if coverage >= 0.6 {
                score += 12
            }
        }

        if overlap == 0, score < 40 {
            return 0
        }
        return score
    }

    private func faqHit(from entry: ReferenceFAQEntry) -> ReferenceKnowledgeHit {
        var tags: [String] = []
        if !entry.intent.isEmpty {
            tags.append(entry.intent)
        }

        return ReferenceKnowledgeHit(
            id: "faq-\(entry.id)",
            title: "FAQ: \(entry.question)",
            snippet: entry.answer,
            pageFrom: nil,
            pageTo: nil,
            tags: tags,
            docID: "uran_faq_300"
        )
    }

    private static let appHints: [ReferenceAppHint] = [
        ReferenceAppHint(
            id: "app_capabilities",
            title: "Что умеет URAN сейчас",
            keywords: [
                "что ты умеешь",
                "что умеет приложение",
                "что умеет uran",
                "возможности приложения",
                "функции приложения",
                "что может uran",
                "срез приложения"
            ],
            answer: """
Сейчас URAN умеет:
1) Поиск препаратов: карточки, МНН, данные из локальной базы.
2) Рецептурный модуль: создание и разбор рецептов, расчеты доз/объемов, проверка части технологических правил.
3) Экстемпоральный блок: формы, техплан, связанные калькуляторы (включая спирт).
4) Ассистент-справочник: диалоговые ответы по компендиуму и базе материалов аптечной технологии.
5) Коммуникация: личные сообщения, группы, форум и вики-заметки.
6) Профиль и пользовательские настройки.

Если нужно, могу подсказать конкретный маршрут по меню под вашу задачу.
"""
        ),
        ReferenceAppHint(
            id: "ethanol_calc",
            title: "Расчет спирта",
            keywords: ["спирт", "этанол", "разведение спирта", "рассчитать спирт", "калькулятор спирта"],
            answer: "Для расчета спирта открой Recipes, затем Экстемпоральный блок и калькулятор спирта. Это можно открыть с главного экрана или найти через поиск."
        ),
        ReferenceAppHint(
            id: "create_recipe",
            title: "Создание рецепта",
            keywords: ["создать рецепт", "напиши рецепт", "сделай рецепт", "рецепт", "магистральный"],
            answer: "Чтобы написать рецепт, зайди в Recipes и открой конструктор рецепта. Я могу помочь текстом: проверить пропись, дозы и последовательность действий."
        ),
        ReferenceAppHint(
            id: "drug_search",
            title: "Поиск препарата",
            keywords: ["поиск препарата", "найти препарат", "лекарство", "поиск лекарств"],
            answer: "Поиск препаратов находится во вкладке Search. Введи название, МНН или часть названия, затем открой карточку препарата."
        ),
        ReferenceAppHint(
            id: "forum_wiki",
            title: "Форум и вики",
            keywords: ["форум", "вики", "заметки", "обсуждение"],
            answer: "Форум находится во вкладке Forum, база заметок и материалов — во вкладке Wiki."
        )
    ]

    private static let capabilitiesTriggers: [String] = [
        "что ты умеешь",
        "что умеет приложение",
        "что умеет uran",
        "возможности приложения",
        "функции приложения",
        "что может uran",
        "срез приложения"
    ]

    private func relevanceScore(
        for chunk: ReferenceKnowledgeChunk,
        normalizedQuery: String,
        tokens: [String]
    ) -> Int {
        var score = 0
        var matchedTokens = 0

        if normalizedQuery.count >= 6 {
            if chunk.searchTitle.contains(normalizedQuery) { score += 20 }
            if chunk.searchBody.contains(normalizedQuery) { score += 14 }
        }

        for token in tokens {
            var matchedCurrentToken = false
            if chunk.searchTitle.contains(token) {
                score += 8
                matchedCurrentToken = true
            }
            if chunk.searchBody.contains(token) {
                score += 4
                matchedCurrentToken = true
            }
            if chunk.searchTags.contains(where: { $0.contains(token) }) {
                score += 5
                matchedCurrentToken = true
            }
            if matchedCurrentToken {
                matchedTokens += 1
            }
        }

        score += min(matchedTokens, 6)
        return score
    }

    private func makeSnippet(from body: String, for tokens: [String]) -> String {
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBody.count <= 340 {
            return cleanBody
        }

        let normalizedBody = normalize(cleanBody)
        var nearestMatchIndex: String.Index?
        for token in tokens {
            if let range = normalizedBody.range(of: token) {
                nearestMatchIndex = range.lowerBound
                break
            }
        }

        guard let match = nearestMatchIndex else {
            let end = cleanBody.index(cleanBody.startIndex, offsetBy: min(320, cleanBody.count))
            return cleanBody[cleanBody.startIndex..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        let distance = normalizedBody.distance(from: normalizedBody.startIndex, to: match)
        let windowStart = max(0, distance - 120)
        let windowEnd = min(cleanBody.count, distance + 220)
        let start = cleanBody.index(cleanBody.startIndex, offsetBy: windowStart)
        let end = cleanBody.index(cleanBody.startIndex, offsetBy: windowEnd)

        var snippet = String(cleanBody[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if windowStart > 0 { snippet = "…" + snippet }
        if windowEnd < cleanBody.count { snippet += "…" }
        return snippet
    }

    private func leadAnswer(from hit: ReferenceKnowledgeHit) -> String {
        var text = hit.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 300 {
            let idx = text.index(text.startIndex, offsetBy: 300)
            text = String(text[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }

    private func contextualClarification(for query: String, fallbackTopic: String) -> String {
        let cleanedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let topic = cleanedQuery.isEmpty ? fallbackTopic : "«\(cleanedQuery)»"
        let templates = [
            "Я пока не вижу в книге точный ответ по \(topic). Уточни форму, концентрацию или операцию (фильтрация/нагрев/смешивание) ))",
            "По \(topic) совпадение не собралось. Дай чуть больше контекста: вещество + лекарственная форма + цель технологии ))",
            "Сейчас по \(topic) прямого попадания нет. Переформулируй запрос предметно, и я доберу материал из книги ))"
        ]
        let index = Int.random(in: 0..<templates.count)
        return templates[index]
    }

    private func tokenized(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .reduce(into: [String]()) { out, token in
                if !out.contains(token) {
                    out.append(token)
                }
            }
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private enum KnowledgeBundleFormat {
        case jsonl
        case json
    }

    private static func loadChunks() throws -> [ReferenceKnowledgeChunk] {
        let candidates: [(name: String, ext: String, subdir: String?, format: KnowledgeBundleFormat)] = [
            ("uran_knowledge_chunks", "jsonl", "uran_book", .jsonl),
            ("uran_knowledge_chunks", "jsonl", nil, .jsonl),
            ("Tikhonov_Aptechnaya_tekhnologia_chunks", "jsonl", "тихонов", .jsonl),
            ("Tikhonov_Aptechnaya_tekhnologia_chunks", "jsonl", nil, .jsonl),
            ("Tikhonov_Aptechnaya_tekhnologia", "json", "тихонов", .json),
            ("Tikhonov_Aptechnaya_tekhnologia", "json", nil, .json)
        ]

        var errors: [String] = []
        for candidate in candidates {
            guard let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext, subdirectory: candidate.subdir) else {
                continue
            }

            do {
                let rawChunks: [RawKnowledgeChunk]
                switch candidate.format {
                case .jsonl:
                    rawChunks = try loadRawChunksFromJSONL(url: url)
                case .json:
                    rawChunks = try loadRawChunksFromJSON(url: url)
                }
                let normalized = normalizeRawChunks(rawChunks)
                if !normalized.isEmpty {
                    return normalized
                }
                errors.append("файл \(candidate.name).\(candidate.ext): после нормализации пусто")
            } catch {
                errors.append("файл \(candidate.name).\(candidate.ext): \(error.localizedDescription)")
            }
        }

        let message = errors.isEmpty
            ? "файл базы знаний не найден в bundle"
            : errors.joined(separator: " | ")
        throw NSError(domain: "ReferenceKnowledge", code: 404, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func loadRawChunksFromJSONL(url: URL) throws -> [RawKnowledgeChunk] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ReferenceKnowledge", code: 422, userInfo: [NSLocalizedDescriptionKey: "jsonl не в UTF-8"])
        }

        var out: [RawKnowledgeChunk] = []
        out.reserveCapacity(1200)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let jsonData = line.data(using: .utf8) else { continue }
            guard let payload = parseRawChunk(from: jsonData) else { continue }
            out.append(payload)
        }
        return out
    }

    private static func loadRawChunksFromJSON(url: URL) throws -> [RawKnowledgeChunk] {
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data)

        var out: [RawKnowledgeChunk] = []
        out.reserveCapacity(1600)

        if let object = root as? [String: Any] {
            if let chunks = object["chunks"] as? [Any] {
                for item in chunks {
                    guard let dict = item as? [String: Any] else { continue }
                    guard let itemData = try? JSONSerialization.data(withJSONObject: dict),
                          let payload = parseRawChunk(from: itemData)
                    else { continue }
                    out.append(payload)
                }
            }

            if let sections = object["sections"] as? [Any] {
                for (idx, item) in sections.enumerated() {
                    guard let dict = item as? [String: Any] else { continue }
                    let title = clean((dict["title"] as? String) ?? "")
                    let text = clean((dict["text"] as? String) ?? "")
                    guard !title.isEmpty, text.count >= 70 else { continue }
                    out.append(
                        RawKnowledgeChunk(
                            chunkID: intValue(dict["id"]) ?? idx,
                            id: intValue(dict["id"]) ?? idx,
                            docID: "tikhonov_aptechnaya_tekhnologia",
                            sourceTitle: "Тихонов — Аптечная технология лекарств",
                            title: title,
                            body: text,
                            pageFrom: intValue(dict["start_line"]),
                            pageTo: intValue(dict["end_line"]),
                            tags: ["TIKHONOV", title]
                        )
                    )
                }
            }
            return out
        }

        if let array = root as? [Any] {
            for item in array {
                guard let dict = item as? [String: Any] else { continue }
                guard let itemData = try? JSONSerialization.data(withJSONObject: dict),
                      let payload = parseRawChunk(from: itemData)
                else { continue }
                out.append(payload)
            }
        }

        return out
    }

    private static func normalizeRawChunks(_ rawChunks: [RawKnowledgeChunk]) -> [ReferenceKnowledgeChunk] {
        var chunks: [ReferenceKnowledgeChunk] = []
        chunks.reserveCapacity(rawChunks.count)

        for (index, payload) in rawChunks.enumerated() {
            let title = clean(payload.title ?? "")
            let body = clean(payload.body ?? "")
            guard !title.isEmpty, body.count >= 70 else { continue }

            let docID = clean(payload.docID ?? payload.sourceTitle ?? "reference")
            let idPart = payload.chunkID ?? payload.id ?? index
            let tags = (payload.tags ?? []).map(clean).filter { !$0.isEmpty }
            chunks.append(
                ReferenceKnowledgeChunk(
                    id: "\(docID)-\(idPart)",
                    docID: docID,
                    title: title,
                    body: body,
                    pageFrom: payload.pageFrom,
                    pageTo: payload.pageTo,
                    tags: tags,
                    searchTitle: title.lowercased(),
                    searchBody: body.lowercased(),
                    searchTags: tags.map { $0.lowercased() }
                )
            )
        }

        return chunks
    }
    private static func loadFAQEntries() throws -> [ReferenceFAQEntry] {
        let candidates: [(name: String, ext: String, subdir: String?)] = [
            ("uran_faq_300", "json", "uran_book"),
            ("uran_faq_300", "json", nil)
        ]

        var selectedURL: URL?
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext, subdirectory: candidate.subdir) {
                selectedURL = url
                break
            }
        }

        guard let url = selectedURL else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }

        var entries: [ReferenceFAQEntry] = []
        entries.reserveCapacity(root.count)

        for raw in root {
            guard let object = raw as? [String: Any] else { continue }
            guard let entry = parseFAQEntry(from: object) else { continue }
            entries.append(entry)
        }

        return entries
    }

    private static func loadNLPAssets() throws -> ReferenceNLPAssets {
        let candidates: [(name: String, ext: String, subdir: String?)] = [
            ("assistant_nlp_assets", "json", "uran_book"),
            ("assistant_nlp_assets", "json", nil)
        ]

        var selectedURL: URL?
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext, subdirectory: candidate.subdir) {
                selectedURL = url
                break
            }
        }

        guard let url = selectedURL else {
            return .empty
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }

        let tokenAliases = parseAliasesMap(root["token_aliases"])
        let phraseAliases = parseAliasesMap(root["phrase_aliases"])
        return ReferenceNLPAssets(tokenAliases: tokenAliases, phraseAliases: phraseAliases)
    }

    private static func parseAliasesMap(_ raw: Any?) -> [String: [String]] {
        guard let object = raw as? [String: Any] else { return [:] }
        var out: [String: [String]] = [:]
        out.reserveCapacity(object.count)

        for (rawKey, rawValue) in object {
            let key = normalizeAliasToken(rawKey)
            guard key.count >= 2 else { continue }
            guard let rawList = rawValue as? [Any] else { continue }

            var aliases: [String] = []
            aliases.reserveCapacity(min(rawList.count, 8))
            for candidate in rawList {
                guard let string = candidate as? String else { continue }
                let alias = normalizeAliasToken(string)
                if alias.count < 2 || alias == key || aliases.contains(alias) {
                    continue
                }
                aliases.append(alias)
            }

            if !aliases.isEmpty {
                out[key] = aliases
            }
        }

        return out
    }

    private static func normalizeAliasToken(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "Только для внутреннего использования", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseRawChunk(from data: Data) -> RawKnowledgeChunk? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let tags: [String]
        if let values = object["tags"] as? [String] {
            tags = values
        } else if let values = object["tags"] as? [Any] {
            tags = values.compactMap { $0 as? String }
        } else {
            tags = []
        }

        let fallbackTitle = object["section_title"] as? String
        let fallbackBody = object["text"] as? String
        let legacySectionId = object["section_id"] as? String
        let hasTikhonovLegacyFields = fallbackBody != nil || fallbackTitle != nil || legacySectionId != nil
        let fallbackDocID = hasTikhonovLegacyFields ? "tikhonov_aptechnaya_tekhnologia" : nil

        var mergedTags = tags
        if mergedTags.isEmpty {
            if let fallbackTitle {
                mergedTags.append(fallbackTitle)
            }
            if hasTikhonovLegacyFields {
                mergedTags.append("TIKHONOV")
            }
        }

        return RawKnowledgeChunk(
            chunkID: intValue(object["chunk_id"]) ?? intValue(object["chunk_index"]),
            id: intValue(object["id"]),
            docID: (object["doc_id"] as? String) ?? fallbackDocID,
            sourceTitle: (object["source_title"] as? String) ?? (hasTikhonovLegacyFields ? "Тихонов — Аптечная технология лекарств" : nil),
            title: (object["title"] as? String) ?? fallbackTitle,
            body: (object["body"] as? String) ?? fallbackBody,
            pageFrom: intValue(object["page_from"]),
            pageTo: intValue(object["page_to"]),
            tags: mergedTags
        )
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct = Int(trimmed) {
                return direct
            }
            if let range = trimmed.range(of: "\\d+", options: .regularExpression) {
                return Int(String(trimmed[range]))
            }
        }
        return nil
    }

    private static func parseFAQEntry(from object: [String: Any]) -> ReferenceFAQEntry? {
        let id = clean((object["id"] as? String) ?? "")
        let question = clean((object["question"] as? String) ?? "")
        let answer = clean((object["answer"] as? String) ?? "")
        let intent = clean((object["intent"] as? String) ?? "")

        if question.count < 3 || answer.count < 3 {
            return nil
        }

        let normalizedQuestion = normalizeAliasToken(question)
        let tokens = normalizedQuestion
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .reduce(into: [String]()) { out, token in
                if !out.contains(token) {
                    out.append(token)
                }
            }

        return ReferenceFAQEntry(
            id: id.isEmpty ? question : id,
            question: question,
            answer: answer,
            intent: intent,
            normalizedQuestion: normalizedQuestion,
            tokens: tokens
        )
    }
}

private struct ReferenceKnowledgeChunk: Sendable {
    let id: String
    let docID: String
    let title: String
    let body: String
    let pageFrom: Int?
    let pageTo: Int?
    let tags: [String]
    let searchTitle: String
    let searchBody: String
    let searchTags: [String]
}

private struct ReferenceFAQEntry: Sendable {
    let id: String
    let question: String
    let answer: String
    let intent: String
    let normalizedQuestion: String
    let tokens: [String]
}

private struct ReferenceNLPAssets: Sendable {
    let tokenAliases: [String: [String]]
    let phraseAliases: [String: [String]]

    nonisolated static let empty = ReferenceNLPAssets(
        tokenAliases: [:],
        phraseAliases: [:]
    )
}

private struct ReferenceAppHint: Sendable {
    let id: String
    let title: String
    let keywords: [String]
    let answer: String

    nonisolated init(id: String, title: String, keywords: [String], answer: String) {
        self.id = id
        self.title = title
        self.keywords = keywords.map { $0.lowercased() }
        self.answer = answer
    }
}

private struct RawKnowledgeChunk {
    let chunkID: Int?
    let id: Int?
    let docID: String?
    let sourceTitle: String?
    let title: String?
    let body: String?
    let pageFrom: Int?
    let pageTo: Int?
    let tags: [String]?

}

private struct PrescriptionSubstanceCatalog {
    struct Entry: Hashable {
        let id: Int?
        let nameRu: String
        let nameLatNom: String
        let nameLatGen: String
        let type: String
        let normalizedRu: String
        let ruTokens: Set<String>
        let ruStems: Set<String>
        let normalizedLatNom: String
        let normalizedLatGen: String
        let latTokens: Set<String>
        let latStems: Set<String>
        let normalizedType: String
    }

    let entries: [Entry]

    static func loadFromBundle() -> PrescriptionSubstanceCatalog {
        guard let url = Bundle.main.url(forResource: "extemp_reference_200", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else {
            return PrescriptionSubstanceCatalog(entries: [])
        }
        let parsed = parseCsvWithHeader(csv)
        guard !parsed.header.isEmpty else { return PrescriptionSubstanceCatalog(entries: []) }

        let headerIndex = buildHeaderIndex(parsed.header)
        func idx(_ names: String...) -> Int? {
            for name in names {
                let key = normalizedHeaderKey(name)
                if let found = headerIndex[key] {
                    return found
                }
            }
            return nil
        }

        guard let latNomIndex = idx("NameLatNom", "name_lat_nom"),
              let latGenIndex = idx("NameLatGen", "name_lat_gen"),
              let typeIndex = idx("Type", "type") else {
            return PrescriptionSubstanceCatalog(entries: [])
        }

        let ruIndex = idx("rus", "name_ru", "NameRu")
        let idIndex = idx("id", "ID")

        var loaded: [Entry] = []
        loaded.reserveCapacity(parsed.rows.count)
        var seenNomKeys: Set<String> = []

        for row in parsed.rows {
            guard latNomIndex < row.count, latGenIndex < row.count, typeIndex < row.count else { continue }
            let latNom = cleaned(row[latNomIndex])
            let latGen = cleaned(row[latGenIndex])
            guard !latNom.isEmpty, !latGen.isEmpty else { continue }
            let nomKey = latNom
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if nomKey.isEmpty || seenNomKeys.contains(nomKey) { continue }
            seenNomKeys.insert(nomKey)

            let type = normalizedReferenceType(cleaned(row[typeIndex]))
            guard !type.isEmpty else { continue }
            let rawRu = ruIndex.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let nameRu = cleaned(rawRu).isEmpty ? latNom : cleaned(rawRu)

            let normalizedRu = normalizedName(nameRu)
            let ruTokens = Set(tokenize(normalizedRu))
            let ruStems = Set(ruTokens.map(stem))
            let normalizedLatNom = normalizedName(latNom)
            let normalizedLatGen = normalizedName(latGen)
            let latCombined = [normalizedLatNom, normalizedLatGen]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let latTokens = Set(tokenize(latCombined))
            let latStems = Set(latTokens.map(stem))
            if ruTokens.isEmpty && ruStems.isEmpty && latTokens.isEmpty && latStems.isEmpty { continue }

            let idValue: Int? = {
                guard let idIndex, idIndex < row.count else { return nil }
                return Int(cleaned(row[idIndex]))
            }()

            loaded.append(
                Entry(
                    id: idValue,
                    nameRu: nameRu,
                    nameLatNom: latNom,
                    nameLatGen: latGen,
                    type: type,
                    normalizedRu: normalizedRu,
                    ruTokens: ruTokens,
                    ruStems: ruStems,
                    normalizedLatNom: normalizedLatNom,
                    normalizedLatGen: normalizedLatGen,
                    latTokens: latTokens,
                    latStems: latStems,
                    normalizedType: type.lowercased()
                )
            )
        }

        return PrescriptionSubstanceCatalog(entries: loaded)
    }

    func bestMatch(for rawQuery: String, preferSolution: Bool) -> Entry? {
        let query = Self.normalizedName(rawQuery)
        guard !query.isEmpty else { return nil }

        let queryTokens = Set(Self.tokenize(query))
        let queryStems = Set(queryTokens.map(Self.stem))
        guard !queryTokens.isEmpty || !queryStems.isEmpty else { return nil }

        var best: Entry?
        var bestScore = Int.min
        var secondBestScore = Int.min

        for entry in entries {
            var score = 0
            if entry.normalizedRu == query {
                score += 140
            }
            if entry.normalizedLatNom == query || entry.normalizedLatGen == query {
                score += 150
            }

            if entry.normalizedRu.contains(query) || query.contains(entry.normalizedRu) {
                score += 30
            }
            if entry.normalizedLatNom.contains(query) || query.contains(entry.normalizedLatNom) {
                score += 34
            }
            if entry.normalizedLatGen.contains(query) || query.contains(entry.normalizedLatGen) {
                score += 38
            }

            let tokenOverlap = queryTokens.intersection(entry.ruTokens).count
            score += tokenOverlap * 20
            if tokenOverlap == queryTokens.count, !queryTokens.isEmpty {
                score += 36
            }
            let latinTokenOverlap = queryTokens.intersection(entry.latTokens).count
            score += latinTokenOverlap * 22
            if latinTokenOverlap == queryTokens.count, !queryTokens.isEmpty {
                score += 44
            }

            let stemOverlap = queryStems.intersection(entry.ruStems).count
            score += stemOverlap * 18
            if stemOverlap == queryStems.count, !queryStems.isEmpty {
                score += 34
            }
            let latinStemOverlap = queryStems.intersection(entry.latStems).count
            score += latinStemOverlap * 20
            if latinStemOverlap == queryStems.count, !queryStems.isEmpty {
                score += 40
            }

            score -= abs(entry.ruTokens.count - queryTokens.count) * 3

            let isSolutionType = entry.normalizedType.contains("solv")
                || entry.normalizedType.contains("solution")
                || entry.normalizedType.contains("liquid")
                || entry.normalizedRu.contains("раствор")
                || entry.normalizedRu.contains("спирт")
            if preferSolution == isSolutionType {
                score += 6
            }

            if score > bestScore {
                secondBestScore = bestScore
                bestScore = score
                best = entry
            } else if score > secondBestScore {
                secondBestScore = score
            }
        }

        guard let best else { return nil }
        let exactMatch = (best.normalizedRu == query)
            || (best.normalizedLatNom == query)
            || (best.normalizedLatGen == query)
        if exactMatch { return best }

        if bestScore < 46 { return nil }
        if secondBestScore != Int.min, (bestScore - secondBestScore) < 8 {
            return nil
        }
        return best
    }

    private static func buildHeaderIndex(_ header: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        out.reserveCapacity(header.count)
        for (index, raw) in header.enumerated() {
            let key = normalizedHeaderKey(raw)
            if !key.isEmpty, out[key] == nil {
                out[key] = index
            }
        }
        return out
    }

    private static func normalizedHeaderKey(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = cleaned.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func parseCsvWithHeader(_ content: String) -> (header: [String], rows: [[String]]) {
        func parseLine(_ line: String) -> [String] {
            var columns: [String] = []
            var current = ""
            var inQuotes = false

            let chars = Array(line)
            var index = 0
            while index < chars.count {
                let ch = chars[index]
                if ch == "\"" {
                    if inQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                        current.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes.toggle()
                    index += 1
                    continue
                }
                if ch == "," && !inQuotes {
                    columns.append(current)
                    current = ""
                    index += 1
                    continue
                }
                current.append(ch)
                index += 1
            }
            columns.append(current)
            return columns
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        guard let first = lines.first else { return ([], []) }
        let header = parseLine(first)
        let rows: [[String]] = lines.dropFirst().compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            var cols = parseLine(trimmed)
            if cols.count > header.count {
                let extra = cols[header.count...]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if extra.contains(where: { !$0.isEmpty }) {
                    return nil
                }
                cols = Array(cols.prefix(header.count))
            } else if cols.count < header.count {
                cols.append(contentsOf: Array(repeating: "", count: header.count - cols.count))
            }
            return cols
        }
        return (header, rows)
    }

    private static func normalizedReferenceType(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        let lower = trimmed.lowercased()
        let compact = lower.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        switch compact {
        case "act", "active", "activeingredient", "substance", "substantia", "medicinalsubstance",
            "insolublepowder", "topicalphytomodern", "ointmentphyto":
            return "act"
        case "aux", "auxiliary", "excipient":
            return "aux"
        case "solv", "solvent", "diluent", "vehicle":
            return "solvent"
        case "base", "ointmentbase", "oilbase", "fattybase", "hydrophobicbase", "polymerbase", "isotonicbase":
            return "base"
        case "buffersolution", "buffer":
            return "buffersolution"
        case "tincture":
            return "tincture"
        case "extract":
            return "extract"
        case "syrup":
            return "syrup"
        case "juice":
            return "juice"
        case "suspension":
            return "suspension"
        case "emulsion":
            return "emulsion"
        case "herbalraw":
            return "herbalraw"
        case "herbalmix":
            return "herbalmix"
        case "liquidstandard", "standardliquid", "standardsolution", "standardstocksolution", "officinalsolution":
            return "standardsolution"
        case "viscousliquid":
            return "viscous liquid"
        case "liquid", "жидкие", "жидкая", "жидкий", "рідкі", "рідка", "рідкий":
            return "liquid"
        case "твердые", "твердый", "твердое", "твердыи", "тверда", "твердий", "тверде":
            return "act"
        case "alcoholic":
            return "alcoholic"
        default:
            return lower
        }
    }

    private static func normalizedName(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    nonisolated private static func stem(_ token: String) -> String {
        var value = token
        guard value.count >= 4 else { return value }

        let endings = [
            "ового", "евого", "иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими",
            "иях", "ах", "ях", "ов", "ев", "ой", "ей", "ий", "ый", "ая", "яя", "ое", "ее",
            "ую", "юю", "а", "я", "у", "ю", "ы", "и", "е", "о"
        ]
        for suffix in endings {
            if value.hasSuffix(suffix), value.count - suffix.count >= 3 {
                value.removeLast(suffix.count)
                return value
            }
        }
        return value
    }

    private static func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ReferenceAssistantMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let hits: [ReferenceKnowledgeHit]
    let actions: [ReferenceAssistantAction]
}

private struct ReferenceAssistantResponse {
    let answerText: String
    let hits: [ReferenceKnowledgeHit]
}

private struct ReferenceAssistantAction: Identifiable {
    enum Kind {
        case compendiumSelection(id: String)
        case openAppDestination(destination: AssistantNavigationDestination)
    }

    let id = UUID()
    let title: String
    let kind: Kind
}

private struct ReferenceKnowledgeHit: Identifiable {
    let id: String
    let title: String
    let snippet: String
    let pageFrom: Int?
    let pageTo: Int?
    let tags: [String]
    let docID: String
}

#Preview {
    NavigationStack {
        ReferenceAssistantView()
    }
}
