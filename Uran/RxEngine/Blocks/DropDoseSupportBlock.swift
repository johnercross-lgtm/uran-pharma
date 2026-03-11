import Foundation

struct DropDoseSupportBlock: RxProcessingBlock {
    static let blockId = "drop_dose_support"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        let measurementLines = DropsAnalysis.buildMeasurementLines(draft: context.draft)
        if !measurementLines.isEmpty {
            context.appendSection(title: "Крапельне дозування", lines: measurementLines)
        }

        let doseCheck = DropsAnalysis.buildDoseChecks(draft: context.draft, signa: context.draft.signa)
        doseCheck.issues.forEach { context.issues.append($0) }
        if !doseCheck.lines.isEmpty {
            context.appendSection(title: "Контроль доз", lines: doseCheck.lines)
        }
    }
}
