import SceneKit
import Testing
@testable import DontCallWaleed
@MainActor struct HouseTests {
    @Test func objectivesAreReachable() {
        let house = House(seed:0)
        for c in house.fuses + House.closets + [House.panel,House.exit] {
            #expect(house.path(from:House.spawn,to:c).last == c)
        }
    }
    @Test func initialSceneLoads() {
        let controller = GameController()
        controller.loadViewIfNeeded()
        #expect(controller.isViewLoaded)
        let renderer = controller.view.subviews.compactMap { $0 as? SCNView }.first
        let root = renderer?.scene?.rootNode
        let face = root?.childNode(withName:"Waleed sculpted face",recursively:true)
        #expect(face?.geometry?.sources(for:.vertex).first?.vectorCount == 252)
        let window = root?.childNode(withName:"Rain window",recursively:true)
        #expect(window?.geometry?.firstMaterial?.diffuse.contents != nil)
        let fuse = root?.childNode(withName:"Glass safety fuse",recursively:true)
        #expect((fuse?.childNodes.count ?? 0) > 8)
        let cupboards = root?.childNodes.filter { $0.name == "Searchable cupboard" } ?? []
        #expect(cupboards.count == 9)
        let storedFuses = cupboards.compactMap { $0.childNode(withName:"Glass safety fuse",recursively:true) }
        #expect(storedFuses.count == 3)
        let hiddenFuses = storedFuses.filter { $0.isHidden }
        #expect(hiddenFuses.count == 3)
        #expect(root?.childNode(withName:"Exit door hinge",recursively:true) != nil)
        #expect(root?.childNode(withName:"Service cabinet key",recursively:true) != nil)
        #expect(root?.childNode(withName:"Security relay 1",recursively:true) != nil)
        #expect(root?.childNode(withName:"Security relay 2",recursively:true) != nil)
    }

    @Test func openingSceneHasStairsAndDoor() {
        let opening = OpeningScene()
        #expect(opening.root.childNodes.count > 50)
        #expect(opening.root.position.x == OpeningLayout.worldX)
        #expect(opening.root.childNode(withName:"Stairwell ceiling",recursively:false) != nil)
        #expect(opening.root.childNode(withName:"Stairwell end wall",recursively:false) != nil)
        #expect(opening.root.childNode(withName:"Garden service breaker",recursively:false) != nil)
        #expect(opening.root.childNode(withName:"Garden rain",recursively:false) != nil)
        #expect(OpeningLayout.walkableInHouse(House(seed:0),x:0,z:OpeningLayout.portalWorldZ))
        opening.reachForKnob()
        #expect(OpeningLayout.floorHeight(at:-3) < OpeningLayout.upperFloor)
        #expect(OpeningLayout.canOpenDoor(x:0,z:OpeningLayout.frontDoorZ+0.72))
        opening.openFrontDoor()
    }

    @Test func documentOpensAndCanClose() {
        let reader = DocumentReader()
        var closed = false
        reader.onClose = { closed = true }
        reader.present(title:"Three knocks",by:"Waleed",body:"Yamen, leave the phone alone.")
        #expect(!reader.isHidden)
        #expect(reader.accessibilityPerformEscape())
        #expect(closed)
    }

    @Test func exteriorIsSolid() { #expect(!House(seed:0).walkable(0,0)) }
}
