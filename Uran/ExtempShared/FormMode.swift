import Foundation

enum FormMode: String, CaseIterable, Identifiable {
    case powders
    case solutions
    case drops
    case suppositories
    case ointments
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powders:
            return "Порошки"
        case .solutions:
            return "Растворы"
        case .drops:
            return "Капли"
        case .suppositories:
            return "Суппозитории"
        case .ointments:
            return "Мази"
        case .auto:
            return "Авто (M.f. из базы)"
        }
    }
}

enum PowderMassMode: String, CaseIterable, Identifiable {
    case dispensa
    case divide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dispensa:
            return "Разделительный (на 1 дозу)"
        case .divide:
            return "Распределительный (общая масса)"
        }
    }
}
