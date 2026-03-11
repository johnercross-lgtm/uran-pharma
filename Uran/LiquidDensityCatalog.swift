import Foundation

struct LiquidDensityCatalogFile: Decodable, Sendable {
    let items: [LiquidDensityEntry]
    let parseIssues: [LiquidDensityParseIssue]?

    enum CodingKeys: String, CodingKey {
        case items
        case parseIssues = "parse_issues"
    }
}

struct LiquidDensityEntry: Decodable, Sendable {
    let name: String
    let densityRaw: String
    let densityRefGml20C: Double

    enum CodingKeys: String, CodingKey {
        case name
        case densityRaw = "density_raw"
        case densityRefGml20C = "density_ref_g_ml_20C"
    }
}

struct LiquidDensityParseIssue: Decodable, Sendable {
    let name: String
}

final class LiquidDensityCatalog: @unchecked Sendable {
    static let shared: LiquidDensityCatalog = {
        do {
            return try loadFromBundle(named: "density_liquids_normalized.json")
        } catch {
            assertionFailure("Failed to load density catalog: \(error.localizedDescription)")
            return LiquidDensityCatalog(entries: [], suspiciousNames: [])
        }
    }()

    private let entriesByName: [String: LiquidDensityEntry]
    private let suspiciousNames: Set<String>

    init(entries: [LiquidDensityEntry], suspiciousNames: Set<String>) {
        self.entriesByName = Dictionary(
            uniqueKeysWithValues: entries.map { (Self.normalize($0.name), $0) }
        )
        self.suspiciousNames = suspiciousNames
    }

    static func loadFromBundle(named fileName: String, bundle: Bundle = .main) throws -> LiquidDensityCatalog {
        guard let url = bundle.url(forResource: fileName, withExtension: nil) else {
            throw EthanolDilutionError.resourceNotFound(name: fileName)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(LiquidDensityCatalogFile.self, from: data)
        let suspicious = Set((decoded.parseIssues ?? []).map { normalize($0.name) })
        return LiquidDensityCatalog(entries: decoded.items, suspiciousNames: suspicious)
    }

    func density(named name: String) -> Double? {
        let key = Self.normalize(name)
        guard !suspiciousNames.contains(key) else { return nil }
        return entriesByName[key]?.densityRefGml20C
    }

    func ethanolDensity(strength: Int) -> Double? {
        density(named: "Спирт этиловый \(strength)%")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
