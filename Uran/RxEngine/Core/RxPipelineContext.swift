import Foundation

struct RxPipelineContext {
    var normalizedDraft: ExtempRecipeDraft
    var facts: RxFacts
    var techPlan: TechPlan = .init()
    var issues: [RxIssue] = []
    var calculations: [String: String] = [:]
    var ppkSections: [PpkSection] = []
    var rxModel: RxRenderModel = .init()
    var activatedBlocks: [String] = []
    var routeBranch: String?
    var powderTechnology: PowderTechnologyResult?

    var draft: ExtempRecipeDraft { normalizedDraft }

    mutating func addIssue(code: String, severity: RxIssueSeverity, message: String) {
        issues.append(RxIssue(code: code, severity: severity, message: message))
    }

    mutating func addStep(_ step: TechStep) {
        techPlan.steps.append(step)
    }

    mutating func appendSection(title: String, lines: [String]) {
        guard !lines.isEmpty else { return }
        if let idx = ppkSections.firstIndex(where: { $0.title == title }) {
            ppkSections[idx].lines.append(contentsOf: lines)
        } else {
            ppkSections.append(PpkSection(title: title, lines: lines))
        }
    }
}
