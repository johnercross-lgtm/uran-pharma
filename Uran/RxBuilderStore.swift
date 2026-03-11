import Foundation
import Combine

@MainActor
final class RxBuilderStore: ObservableObject {

    @Published private(set) var draft = ExtempRecipeDraft()
    @Published private(set) var normalizedDraft = ExtempRecipeDraft()
    @Published private(set) var issues: [RxIssue] = []
    @Published private(set) var techPlan = TechPlan()
    @Published private(set) var derived = DerivedState()
    @Published private(set) var rxText: String = ""
    @Published private(set) var ppkText: String = ""

    private let engine: RuleEngineProtocol
    private let outputPipeline = RxOutputPipeline()
    private var outputConfig = RxOutputRenderConfig()

    init() {
        self.engine = DefaultRuleEngine()
        reevaluate()
    }

    init(engine: RuleEngineProtocol) {
        self.engine = engine
        reevaluate()
    }

    func update(_ mutation: (inout ExtempRecipeDraft) -> Void) {
        mutation(&draft)
        reevaluate()
    }

    func configureOutput(_ config: RxOutputRenderConfig) {
        outputConfig = config
        reevaluate()
    }

    private func reevaluate() {
        let result = engine.evaluate(draft: draft)
        normalizedDraft = result.normalizedDraft
        issues = result.issues
        techPlan = result.techPlan
        derived = result.derived

        let output = outputPipeline.render(
            draft: normalizedDraft,
            derived: derived,
            issues: issues,
            techPlan: techPlan,
            config: outputConfig
        )
        rxText = output.rxText
        ppkText = output.ppkText
    }
}
