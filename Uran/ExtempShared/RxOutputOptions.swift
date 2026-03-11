import Foundation

enum BelladonnaExtractVariant: String, CaseIterable, Identifiable {
    case densum
    case siccum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .densum:
            return "Густий (densum)"
        case .siccum:
            return "Сухий (siccum, ×2)"
        }
    }
}

enum RxBlankType: String, CaseIterable, Identifiable {
    case ordinary
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ordinary:
            return "Обычный"
        case .strict:
            return "Строгий"
        }
    }

    var rxHeader: String {
        switch self {
        case .ordinary:
            return "Rp.:"
        case .strict:
            return "Recipe:"
        }
    }
}
