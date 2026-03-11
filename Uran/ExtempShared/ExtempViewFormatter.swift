import Foundation

enum ExtempViewFormatter {
    nonisolated static func formatAmount(_ value: Double) -> String {
        let source = String(format: "%.4f", value)
        var output = source
        while output.contains(".") && (output.hasSuffix("0") || output.hasSuffix(".")) {
            if output.hasSuffix("0") {
                output.removeLast()
                continue
            }
            if output.hasSuffix(".") {
                output.removeLast()
                break
            }
        }
        return output.replacingOccurrences(of: ".", with: ",")
    }

    nonisolated static func formatPercentRange(_ range: PercentRange?) -> String {
        guard let range else { return "—" }
        switch (range.min, range.max) {
        case let (.some(min), .some(max)):
            return "\(formatPercentValue(min))–\(formatPercentValue(max))"
        case let (.some(min), .none):
            return "≥\(formatPercentValue(min))"
        case let (.none, .some(max)):
            return "≤\(formatPercentValue(max))"
        default:
            return "—"
        }
    }

    nonisolated static func formatPercentValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    nonisolated static func referenceMetaLine(for substance: ExtempSubstance) -> String {
        let type = substance.refType.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !type.isEmpty { parts.append(type) }
        if let vrd = substance.vrdG {
            parts.append("ВРД: \(formatAmount(vrd)) g")
        }
        if let vsd = substance.vsdG {
            parts.append("ВСД: \(formatAmount(vsd)) g")
        }
        if let kuo = substance.kuoMlPerG {
            parts.append("КУО: \(formatAmount(kuo)) мл/г")
        }
        if let kv = substance.kvGPer100G {
            parts.append("КВ: \(formatAmount(kv))")
        }
        return parts.joined(separator: " · ")
    }
}
