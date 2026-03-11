import Foundation

struct EthanolTablesFile: Decodable, Sendable {
    let schema: String
    let tables: [EthanolDilutionTable]
}

struct EthanolDilutionTable: Decodable, Sendable {
    let id: String
    let version: Int
    let basis: Basis
    let unit: UnitKind
    let targetsPercent: [Int]
    let rows: [Row]

    struct Basis: Decodable, Sendable {
        let temperatureC: Double
        let resultMassG: Double?
        let resultVolumeML: Double?

        enum CodingKeys: String, CodingKey {
            case temperatureC
            case resultMassG = "resultMass_g"
            case resultVolumeML = "resultVolume_ml"
        }
    }

    enum UnitKind: String, Decodable, Sendable {
        case g
        case ml
    }

    struct Row: Decodable, Sendable {
        let sourcePercent: Double
        let parts: [String: Parts]
    }

    struct Parts: Decodable, Sendable {
        let ethanol: Double
        let water: Double
    }

    struct Lookup: Sendable {
        let parts: Parts
        let resolvedSourcePercent: Double
        let usedNearestSource: Bool
        let interpolatedTargetRange: ClosedRange<Int>?
    }

    var baseAmount: Double? {
        basis.resultMassG ?? basis.resultVolumeML
    }

    func supportedTargets() -> Set<Int> {
        Set(targetsPercent)
    }

    func exactParts(sourcePercent: Double, targetPercent: Int) -> Lookup? {
        guard let row = rows.first(where: { abs($0.sourcePercent - sourcePercent) < 0.0001 }),
              let parts = row.parts[String(targetPercent)] else {
            return nil
        }
        return Lookup(
            parts: parts,
            resolvedSourcePercent: row.sourcePercent,
            usedNearestSource: false,
            interpolatedTargetRange: nil
        )
    }

    private func resolvedRow(sourcePercent: Double, maxDistance: Double) -> (row: Row, usedNearestSource: Bool)? {
        if let exact = rows.first(where: { abs($0.sourcePercent - sourcePercent) < 0.0001 }) {
            return (exact, false)
        }
        let sortedRows = rows.sorted {
            abs($0.sourcePercent - sourcePercent) < abs($1.sourcePercent - sourcePercent)
        }
        guard let row = sortedRows.first,
              abs(row.sourcePercent - sourcePercent) <= maxDistance else {
            return nil
        }
        return (row, true)
    }

    private func interpolatedParts(row: Row, targetPercent: Int) -> (parts: Parts, range: ClosedRange<Int>)? {
        let availableTargets = row.parts.keys.compactMap(Int.init).sorted()
        guard let lower = availableTargets.last(where: { $0 < targetPercent }),
              let upper = availableTargets.first(where: { $0 > targetPercent }),
              let lowerParts = row.parts[String(lower)],
              let upperParts = row.parts[String(upper)],
              upper > lower else {
            return nil
        }

        let factor = Double(targetPercent - lower) / Double(upper - lower)
        return (
            parts: Parts(
                ethanol: lowerParts.ethanol + (upperParts.ethanol - lowerParts.ethanol) * factor,
                water: lowerParts.water + (upperParts.water - lowerParts.water) * factor
            ),
            range: lower...upper
        )
    }

    func lookup(sourcePercent: Double, targetPercent: Int, maxSourceDistance: Double = 1.0) -> Lookup? {
        guard let resolvedRow = resolvedRow(sourcePercent: sourcePercent, maxDistance: maxSourceDistance) else {
            return nil
        }

        if let exactParts = resolvedRow.row.parts[String(targetPercent)] {
            return Lookup(
                parts: exactParts,
                resolvedSourcePercent: resolvedRow.row.sourcePercent,
                usedNearestSource: resolvedRow.usedNearestSource,
                interpolatedTargetRange: nil
            )
        }

        guard let interpolated = interpolatedParts(row: resolvedRow.row, targetPercent: targetPercent) else {
            return nil
        }

        return Lookup(
            parts: interpolated.parts,
            resolvedSourcePercent: resolvedRow.row.sourcePercent,
            usedNearestSource: resolvedRow.usedNearestSource,
            interpolatedTargetRange: interpolated.range
        )
    }

    func scaled(sourcePercent: Double, targetPercent: Int, resultAmount: Double) -> Lookup? {
        guard let base = baseAmount, base > 0 else { return nil }
        guard let resolved = lookup(sourcePercent: sourcePercent, targetPercent: targetPercent) else {
            return nil
        }

        let scale = resultAmount / base
        return Lookup(
            parts: Parts(
                ethanol: resolved.parts.ethanol * scale,
                water: resolved.parts.water * scale
            ),
            resolvedSourcePercent: resolved.resolvedSourcePercent,
            usedNearestSource: resolved.usedNearestSource,
            interpolatedTargetRange: resolved.interpolatedTargetRange
        )
    }
}

enum EthanolDilutionMode: Sendable {
    case massG
    case volumeML
}

enum EthanolDilutionError: Error, LocalizedError, Sendable {
    case resourceNotFound(name: String)
    case tableNotFound(mode: EthanolDilutionMode)
    case pairNotFound(source: Double, target: Int, mode: EthanolDilutionMode)
    case invalidAmount
    case invalidStrengthOrder(source: Double, target: Int)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Ethanol tables resource not found: \(name)"
        case .tableNotFound(let mode):
            return "Ethanol dilution table not found for mode: \(mode)"
        case .pairNotFound(let source, let target, let mode):
            return "No dilution entry for source \(source)% -> target \(target)% (mode: \(mode))"
        case .invalidAmount:
            return "Invalid final amount (must be > 0)"
        case .invalidStrengthOrder(let source, let target):
            return "Source concentration \(source)% must be higher than or equal to target \(target)%"
        }
    }
}

struct EthanolDilutionResult: Sendable {
    let mode: EthanolDilutionMode
    let requestedSourcePercent: Double
    let resolvedSourcePercent: Double
    let targetPercent: Int
    let ethanol: Double
    let water: Double
    let finalAmount: Double
    let tableID: String
    let temperatureC: Double
    let mixAmountBeforeContraction: Double
    let usedNearestSource: Bool
    let interpolatedTargetRange: ClosedRange<Int>?
    let instruction: String

    var unit: EthanolDilutionTable.UnitKind {
        switch mode {
        case .massG:
            return .g
        case .volumeML:
            return .ml
        }
    }
}

final class EthanolDilutionRepository: @unchecked Sendable {
    private enum TableID {
        static let mass = "ethanol_dilution_table_5_5_2_mass"
        static let volumeMain = "ethanol_dilution_table_5_5_3_volume_main"
        static let volumeCont95 = "ethanol_dilution_table_5_5_3_volume_cont_95"
    }

    static let shared: EthanolDilutionRepository = {
        do {
            return try loadFromBundle(named: "ethanol_tables.json")
        } catch {
            assertionFailure("Failed to load ethanol tables: \(error.localizedDescription)")
            return EthanolDilutionRepository(tables: [])
        }
    }()

    private let tables: [EthanolDilutionTable]

    init(tables: [EthanolDilutionTable]) {
        self.tables = tables
    }

    static func loadFromBundle(named fileName: String, bundle: Bundle = .main) throws -> EthanolDilutionRepository {
        guard let url = bundle.url(forResource: fileName, withExtension: nil) else {
            throw EthanolDilutionError.resourceNotFound(name: fileName)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(EthanolTablesFile.self, from: data)
        return EthanolDilutionRepository(tables: decoded.tables)
    }

    func supportedTargets(for mode: EthanolDilutionMode) -> Set<Int> {
        switch mode {
        case .massG:
            return Set(table(id: TableID.mass)?.targetsPercent ?? [])
        case .volumeML:
            return Set(volumeTables().flatMap(\.targetsPercent))
        }
    }

    func prepareEthanol(
        sourcePercent: Double,
        targetPercent: Int,
        finalAmount: Double,
        mode: EthanolDilutionMode
    ) throws -> EthanolDilutionResult {
        guard finalAmount > 0 else {
            throw EthanolDilutionError.invalidAmount
        }
        guard sourcePercent + 0.0001 >= Double(targetPercent) else {
            throw EthanolDilutionError.invalidStrengthOrder(source: sourcePercent, target: targetPercent)
        }

        switch mode {
        case .massG:
            guard let table = table(id: TableID.mass) else {
                throw EthanolDilutionError.tableNotFound(mode: .massG)
            }
            guard let resolved = table.scaled(
                sourcePercent: sourcePercent,
                targetPercent: targetPercent,
                resultAmount: finalAmount
            ) else {
                throw EthanolDilutionError.pairNotFound(source: sourcePercent, target: targetPercent, mode: .massG)
            }

            return EthanolDilutionResult(
                mode: .massG,
                requestedSourcePercent: sourcePercent,
                resolvedSourcePercent: resolved.resolvedSourcePercent,
                targetPercent: targetPercent,
                ethanol: resolved.parts.ethanol,
                water: resolved.parts.water,
                finalAmount: finalAmount,
                tableID: table.id,
                temperatureC: table.basis.temperatureC,
                mixAmountBeforeContraction: resolved.parts.ethanol + resolved.parts.water,
                usedNearestSource: resolved.usedNearestSource,
                interpolatedTargetRange: resolved.interpolatedTargetRange,
                instruction: "Змішати компоненти за табличними масами при 20°C."
            )

        case .volumeML:
            guard let table = volumeTable(for: targetPercent) else {
                throw EthanolDilutionError.tableNotFound(mode: .volumeML)
            }
            guard let resolved = table.scaled(
                sourcePercent: sourcePercent,
                targetPercent: targetPercent,
                resultAmount: finalAmount
            ) else {
                throw EthanolDilutionError.pairNotFound(source: sourcePercent, target: targetPercent, mode: .volumeML)
            }
            return EthanolDilutionResult(
                mode: .volumeML,
                requestedSourcePercent: sourcePercent,
                resolvedSourcePercent: resolved.resolvedSourcePercent,
                targetPercent: targetPercent,
                ethanol: resolved.parts.ethanol,
                water: resolved.parts.water,
                finalAmount: finalAmount,
                tableID: table.id,
                temperatureC: table.basis.temperatureC,
                mixAmountBeforeContraction: resolved.parts.ethanol + resolved.parts.water,
                usedNearestSource: resolved.usedNearestSource,
                interpolatedTargetRange: resolved.interpolatedTargetRange,
                instruction: "Відміряти окремо спирт і воду за таблицею при 20°C, змішати та отримати кінцевий об'єм за рахунок контракції."
            )
        }
    }

    private func table(id: String) -> EthanolDilutionTable? {
        tables.first(where: { $0.id == id })
    }

    private func volumeTables() -> [EthanolDilutionTable] {
        [TableID.volumeMain, TableID.volumeCont95].compactMap { table(id: $0) }
    }

    private func volumeTable(for targetPercent: Int) -> EthanolDilutionTable? {
        let tables = volumeTables()
        if let exact = tables.first(where: { $0.targetsPercent.contains(targetPercent) }) {
            return exact
        }
        return tables.first(where: { table in
            let sorted = table.targetsPercent.sorted()
            guard let lower = sorted.last(where: { $0 < targetPercent }),
                  let upper = sorted.first(where: { $0 > targetPercent }) else {
                return false
            }
            return lower < targetPercent && targetPercent < upper
        })
    }
}
