import Testing
@testable import DontCallWaleed
@MainActor struct HouseTests {
    @Test func objectivesAreReachable() {
        for c in House.fuses + House.closets + [House.panel,House.exit] {
            #expect(House.path(from:House.spawn,to:c).last == c)
        }
    }
    @Test func exteriorIsSolid() { #expect(!House.walkable(0,0)) }
}
