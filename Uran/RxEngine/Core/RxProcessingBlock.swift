import Foundation

struct ModularRxEngineOutput {
    var techPlan: TechPlan
    var issues: [RxIssue]
    var derived: DerivedState
}

protocol RxProcessingBlock {
    var id: String { get }
    func apply(context: inout RxPipelineContext)
}
