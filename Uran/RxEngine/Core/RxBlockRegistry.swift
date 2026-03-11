import Foundation

struct RxBlockRegistryItem {
    let id: String
    let priority: Int
    let block: any RxProcessingBlock
}

struct RxBlockRegistry {
    private let items: [RxBlockRegistryItem]

    init(items: [RxBlockRegistryItem]) {
        self.items = items
    }

    func orderedBlocks(for selectedIds: Set<String>) -> [any RxProcessingBlock] {
        items
            .filter { selectedIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.id < rhs.id
            }
            .map(\.block)
    }

    static func `default`() -> RxBlockRegistry {
        RxBlockRegistry(items: [
            .init(id: BaseTechnologyBlock.blockId, priority: 0, block: BaseTechnologyBlock()),
            .init(id: PoisonControlBlock.blockId, priority: 4, block: PoisonControlBlock()),
            .init(id: StrongControlBlock.blockId, priority: 5, block: StrongControlBlock()),
            .init(id: PowdersTriturationsBlock.blockId, priority: 6, block: PowdersTriturationsBlock()),
            .init(id: SuppositoriesBlock.blockId, priority: 7, block: SuppositoriesBlock()),
            .init(id: OintmentsBlock.blockId, priority: 8, block: OintmentsBlock()),
            .init(id: StandardSolutionsBlock.blockId, priority: 10, block: StandardSolutionsBlock()),
            .init(id: VMSColloidsBlock.blockId, priority: 20, block: VMSColloidsBlock()),
            .init(id: NonAqueousSolutionsBlock.blockId, priority: 30, block: NonAqueousSolutionsBlock()),
            .init(id: BuretteSystemBlock.blockId, priority: 35, block: BuretteSystemBlock()),
            .init(id: WaterSolutionsBlock.blockId, priority: 40, block: WaterSolutionsBlock()),
            .init(id: DropDoseSupportBlock.blockId, priority: 45, block: DropDoseSupportBlock()),
            .init(id: OphthalmicDropsBlock.blockId, priority: 49, block: OphthalmicDropsBlock()),
            .init(id: DropsBlock.blockId, priority: 50, block: DropsBlock()),
            .init(id: InfusionDecoctionBlock.infusionBlockId, priority: 60, block: InfusionDecoctionBlock(mode: .infusion)),
            .init(id: InfusionDecoctionBlock.decoctionBlockId, priority: 61, block: InfusionDecoctionBlock(mode: .decoction))
        ])
    }
}
