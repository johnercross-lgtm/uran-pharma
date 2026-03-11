import Foundation

struct WikiRecipeItem: Identifiable, Hashable {
    var id: String { uaVariantId }

    let uaVariantId: String
    let title: String

    let doseText: String
    let quantityN: String
    let formRaw: String
    let signaText: String

    let updatedByUid: String
    let updatedAt: Date?
}
