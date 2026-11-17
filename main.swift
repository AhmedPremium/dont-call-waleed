import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let house = House(seed:0)
let objectives = house.fuses + House.closets + [House.panel, House.exit, House.enemy]
for target in objectives {
    let route = house.path(from:House.spawn,to:target)
    check(route.last == target, "Unreachable objective")
    var previous = House.spawn
    for c in route {
        check(house.open(c), "Path crosses wall")
        check(abs(c.x-previous.x)+abs(c.z-previous.z) == 1, "Path skips cells")
        check(house.walkable((Float(c.x)+0.5)*House.tile,(Float(c.z)+0.5)*House.tile), "Cell center is blocked")
        previous = c
    }
}
for a in house.patrol {
    for b in house.patrol where a != b { check(house.path(from:a,to:b).last == b,"Patrol disconnected") }
}
check(!house.walkable(0,0), "Outside world must be solid")
check(!house.visible(7.5*House.tile,2.5*House.tile,9.5*House.tile,2.5*House.tile),"Wall must block sight")
check(house.visible(2.5*House.tile,3.5*House.tile,12.5*House.tile,3.5*House.tile),"Open hall must allow sight")
// At 60 Hz this chase step can skip the old 0.06–0.08 handoff window.
var remaining: Float = 0.09
var updates = 0
while !House.reachedWaypoint(remaining) && updates < 10 {
    remaining -= min(remaining, 2.25/60)
    updates += 1
}
check(updates == 3 && House.reachedWaypoint(remaining), "Enemy must consume the waypoint after a skipped threshold")
check(House.reachedWaypoint(0), "Enemy must consume an already reached waypoint")
let nearWallX = 7.8*House.tile
check(house.canCatch(enemyX:nearWallX,enemyZ:2.25*House.tile,playerX:nearWallX,playerZ:2.75*House.tile), "Waleed should catch a reachable player beside the same wall")
check(!house.canCatch(enemyX:7.88*House.tile,enemyZ:2.68*House.tile,playerX:8.12*House.tile,playerZ:3.12*House.tile), "Waleed must not catch the player diagonally through a wall")
let utilityDoor = house.doorways.first { $0.cell.z == 5 && $0.cell.x < 8 }!.cell
let hallX = (Float(utilityDoor.x)+0.5)*House.tile
check(house.walkableBetween(hallX,4.5*House.tile,hallX,6.5*House.tile,radius:0.18), "An open doorway should allow a direct chase")
check(!house.walkableBetween(6.5*House.tile,4.5*House.tile,6.5*House.tile,6.5*House.tile,radius:0.18), "A blocked doorway approach must use the patrol grid")
let search = house.searchCells(near:House.spawn)
check(search.count == 3 && Set(search).count == 3, "Search should cover distinct reachable cells")
check(search.allSatisfy { (2...4).contains(house.path(from:House.spawn,to:$0).count) }, "Search should stay around the last known position")
print("House validation passed: all objectives reachable, patrol connected, walls block movement and sight.")

var maps = Set<String>()
var fuseSets = Set<[Cell]>()
for seed in 0..<32 {
    let layout = House(seed:UInt64(seed))
    maps.insert(layout.rows.map { String($0) }.joined())
    fuseSets.insert(layout.fuses)
    check(layout.rows.allSatisfy { $0.count == 17 }, "Compact house has malformed rows")
    check(layout.doorways.count == 7, "Seven interior doorways must have doors")
    for x in (House.sunroomWindow.x-1)...(House.sunroomWindow.x+1) {
        check(!layout.open(Cell(x:x,z:House.sunroomWindow.z-1)),
              "The window and curtains must never overlap an interior doorway")
    }
    for doorway in layout.doorways {
        let p = doorway.cell
        check(layout.path(from:House.spawn,to:p).last == p, "A door is outside the reachable floor")
    }
    let cupboardCells = House.cupboards.map(\.cell)
    check(Set(layout.fuses).count == 3 && layout.fuses.allSatisfy(cupboardCells.contains),
          "Exactly three cupboards must contain a fuse")
    for site in House.cupboards {
        let cupboard = site.cell
        let x = (Float(cupboard.x)+0.5)*House.tile
        let z = (Float(cupboard.z)+0.5)*House.tile
        let backX = x+Float(site.wallX)*House.cupboardOffset
        let backZ = z+Float(site.wallZ)*House.cupboardOffset
        let tangentX = -Float(site.wallZ)*0.56
        let tangentZ = Float(site.wallX)*0.56
        check(!layout.open(site.wall),"A cupboard must be backed by a fixed wall")
        check(!layout.walkable(backX,backZ),"Cupboards must block movement")
        check(layout.walkable(x,z),"A player must be able to stand at the front of every cupboard")
        check(!layout.canCatch(enemyX:backX-tangentX,enemyZ:backZ-tangentZ,
                               playerX:backX+tangentX,playerZ:backZ+tangentZ),
              "Waleed cannot grab through a cupboard")
    }
    for fixture in [House.loungeTV,House.laundryWasher,House.studyShelves] {
        check(!layout.open(Cell(x:fixture.x,z:fixture.z-1)),
              "Wall furniture must stay away from a doorway when layouts change")
    }
    for i in 0...30 {
        let x = -1+Float(i)*0.10
        check(OpeningLayout.walkableInHouse(layout,x:x,z:OpeningLayout.portalWorldZ),
              "Foyer must remain connected to downstairs map")
    }
    check(!OpeningLayout.walkableInHouse(layout,x:-0.06,z:OpeningLayout.portalWorldZ+1.3),
          "Foyer walls must remain solid away from the opening")
    let missions = [House.exit,House.panel,House.foyerEntrance,House.serviceDesk,House.kitchenRelay,House.laundryRelay]
    for cell in cupboardCells + layout.patrol + House.closets + missions {
        let route = layout.path(from:House.spawn,to:cell)
        check(route.last == cell, "Seed \(seed) has an unreachable objective or patrol point")
        for (start,end) in zip([House.spawn]+route,route) {
            let ax = (Float(start.x)+0.5)*House.tile, az = (Float(start.z)+0.5)*House.tile
            let bx = (Float(end.x)+0.5)*House.tile, bz = (Float(end.z)+0.5)*House.tile
            check(layout.walkableBetween(ax,az,bx,bz,radius:0.18), "Patrol path intersects a furnishing")
        }
    }
    check(!layout.walkable(12.5*House.tile,1.5*House.tile-0.93),"Fridge must block movement")
    check(layout.walkable(12.5*House.tile,1.5*House.tile),"Kitchen walkway must stay open")
    for z in layout.rows.indices {
        for x in layout.rows[z].indices {
            let cell = Cell(x:x,z:z)
            if layout.open(cell), cell != House.spawn {
                check(layout.path(from:House.spawn,to:cell).last == cell, "Seed \(seed) has an isolated room")
            }
        }
    }
}
check(maps.count > 1 && fuseSets.count > 1, "Replay must vary both the floor plan and fuse placement")
print("Validated 32 layouts: all rooms, fuses, hiding spots, and patrol points are reachable.")

let bedside = OpeningLayout.bedside
check(OpeningLayout.walkable(x:bedside.x,z:bedside.z), "Player must be able to stand beside the bed")
check(!OpeningLayout.walkable(x:-2,z:4.25), "Player cannot walk through the bed")
check(!OpeningLayout.walkable(x:1.18,z:-3), "Player cannot cross the staircase railing")
let entrance = OpeningLayout.frontDoorZ+0.72
check(OpeningLayout.canOpenDoor(x:0,z:entrance), "The downstairs front door must be actionable")
check(!OpeningLayout.canOpenDoor(x:0,z:bedside.z), "The front door cannot be opened from upstairs")
var lastHeight = OpeningLayout.upperFloor
for i in 0...140 {
    let z = bedside.z+(entrance-bedside.z)*Float(i)/140
    check(OpeningLayout.walkable(x:bedside.x,z:z), "Route from the bed to the front door must be clear")
    let height = OpeningLayout.floorHeight(at:z)
    check(height <= lastHeight && lastHeight-height < 0.12, "Stair descent must be continuous")
    lastHeight = height
}
check(lastHeight == 0,"Player must reach the downstairs floor")
print("Validated the prologue route from upstairs bed to downstairs front door.")

check(House.canNotice(range:1,forward:1,flashlight:true,crouched:true), "Waleed must see a crouched player at close range")
check(!House.canNotice(range:4,forward:4,flashlight:false,crouched:true), "Crouching reduces detection range")
check(!House.canNotice(range:4,forward:-4,flashlight:false,crouched:false), "Patrol vision should not detect players behind Waleed")
check(House.canNotice(range:4,forward:4,flashlight:false,crouched:false), "Visible standing players should still be detected")

// Check both player choices and a missed call without wall-clock timing.
var answered = BreakerEncounter()
answered.start(at:0)
check(answered.isLit(at:0.10) && !answered.isLit(at:0.29),"The breaker must flicker")
check(answered.advance(to:1) == nil,"Call must wait for the flicker")
check(answered.advance(to:2) == .ring && answered.answer(at:3),"Breaker call can be answered")
check(answered.advance(to:5) == nil && answered.advance(to:6) == .knock,"Knock follows the voice")
check(answered.advance(to:7) == nil && answered.advance(to:9) == .clue,"Listening earns the exit clue")
check(answered.advance(to:10) == nil,"The scene must only play once")
var earlyHangup = BreakerEncounter()
earlyHangup.start(at:0)
check(earlyHangup.advance(to:2) == .ring && earlyHangup.answer(at:3) && earlyHangup.hangUp(),"Player can hang up")
check(earlyHangup.advance(to:10) == nil && !earlyHangup.isActive,"Hanging up suppresses the knocks and clue")
var missed = BreakerEncounter()
missed.start(at:0)
check(missed.advance(to:2) == .ring && missed.advance(to:14) == .missed,"Unanswered calls expire")
check(!missed.answer(at:15),"An expired call cannot be answered")
print("Validated all three breaker call outcomes.")

let retryLayout = House(seed:12)
let freshLayout = retryLayout.reshuffled()
check(freshLayout.rows != retryLayout.rows || freshLayout.fuses != retryLayout.fuses, "New layout must change the floor plan or fuse placement")
for stop in [House.fridgeStop,House.listeningStop,House.sofaStop] {
    check(retryLayout.patrol.contains(stop), "Patrol must visit each activity")
}
print("Validated a distinct new layout and all three patrol stops.")

for (beat,time) in zip(EscapeSequence.Beat.allCases,EscapeSequence.cues) {
    check(EscapeSequence.beat(at:time) == beat,"Ending must play its cues in order")
}
check(EscapeSequence.beat(at:20) == .results,"Ending must settle at the results screen")
print("Validated the escape cutscene cue order.")

let frontZ = OpeningLayout.worldZ+OpeningLayout.frontDoorZ
let frontX = OpeningLayout.worldX
check(!OpeningLayout.walkableWithGarden(house,x:frontX,z:frontZ,doorOpen:false),"The closed door blocks the garden route")
for t in 0...72 {
    let z = frontZ+0.50-Float(t)*0.10
    check(OpeningLayout.walkableWithGarden(house,x:frontX,z:z,doorOpen:true),"The open door connects the house and the garden path")
}
let breaker = OpeningLayout.gardenBox
check(OpeningLayout.walkableWithGarden(house,x:frontX+1,z:OpeningLayout.worldZ+breaker.z,doorOpen:true),
      "Yamen must be able to approach the garden breaker")
var story = StoryProgress()
check(!story.advance(.releaseExit), "The exit must remain locked during the opening")
check(story.advance(.closeRainDoor) && story.stage == .garden, "Opening must hand control back for the garden objective")
check(story.advance(.resetGardenPower) && story.stage == .retreat, "Restoring house power starts the retreat")
check(!story.advance(.watchBroadcast) && story.advance(.lockFrontDoor), "The front door must be locked before watching the news")
check(story.advance(.watchBroadcast) && story.advance(.installFuses) && story.advance(.takeKey), "The middle objectives must link up")
check(story.advance(.resetRelay(House.laundryRelay)) && !story.advance(.resetRelay(House.laundryRelay)),
      "A repeated relay cannot satisfy both objectives")
check(!story.advance(.releaseExit) && story.advance(.resetRelay(House.kitchenRelay)), "Both relays are required")
check(story.advance(.releaseExit) && story.stage == .exit, "The study console must release the back door")
print("Validated all garden and story objectives, the relay interlock, and close-range crouch detection.")
