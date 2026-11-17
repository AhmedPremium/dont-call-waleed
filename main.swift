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
    for doorway in layout.doorways {
        let p = doorway.cell
        check(layout.path(from:House.spawn,to:p).last == p, "A door is outside the reachable floor")
    }
    for fuse in layout.fuses {
        let x = (Float(fuse.x)+0.5)*House.tile
        let z = (Float(fuse.z)+0.5)*House.tile
        check(!layout.walkable(x,z+House.fuseTableShift-0.18),"Fuse table must block movement")
        check(layout.walkable(x,z),"A player must be able to reach the fuse table")
        check(!layout.canCatch(enemyX:x-0.55,enemyZ:z+House.fuseTableShift-0.18,
                               playerX:x+0.55,playerZ:z+House.fuseTableShift-0.18),
              "Waleed cannot grab through the fuse table")
    }
    for i in 0...30 {
        let x = -1+Float(i)*0.10
        check(OpeningLayout.walkableInHouse(layout,x:x,z:OpeningLayout.portalWorldZ),
              "Foyer must remain connected to downstairs map")
    }
    check(!OpeningLayout.walkableInHouse(layout,x:-0.06,z:OpeningLayout.portalWorldZ+1.3),
          "Foyer walls must remain solid away from the opening")
    for cell in layout.fuses + layout.patrol + House.closets + [House.exit,House.panel,House.foyerEntrance] {
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
