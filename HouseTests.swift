import Testing
@testable import DontCallWaleed
@MainActor struct HouseTests {
    @Test func objectivesAreReachable() {
        let house = House(seed:0)
        for c in house.fuses + House.closets + [House.panel,House.exit] {
            #expect(house.path(from:House.spawn,to:c).last == c)
        }
    }
    @Test func exteriorIsSolid() { #expect(!House(seed:0).walkable(0,0)) }
}
