import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let objectives = House.fuses + House.closets + [House.panel, House.exit, House.enemy]
for target in objectives {
    let route = House.path(from:House.spawn,to:target)
    check(route.last == target, "Unreachable objective")
    var previous = House.spawn
    for c in route {
        check(House.open(c), "Path crosses wall")
        check(abs(c.x-previous.x)+abs(c.z-previous.z) == 1, "Path skips cells")
        check(House.walkable((Float(c.x)+0.5)*House.tile,(Float(c.z)+0.5)*House.tile), "Cell center is blocked")
        previous = c
    }
}
for a in House.patrol {
    for b in House.patrol where a != b { check(House.path(from:a,to:b).last == b,"Patrol disconnected") }
}
check(!House.walkable(0,0), "Outside world must be solid")
check(!House.visible(7.5*House.tile,2.5*House.tile,9.5*House.tile,2.5*House.tile),"Wall must block sight")
check(House.visible(2.5*House.tile,3.5*House.tile,12.5*House.tile,3.5*House.tile),"Open hall must allow sight")
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
check(House.canCatch(enemyX:nearWallX,enemyZ:2.25*House.tile,playerX:nearWallX,playerZ:2.75*House.tile), "Waleed should catch a reachable player beside the same wall")
check(!House.canCatch(enemyX:7.88*House.tile,enemyZ:2.68*House.tile,playerX:8.12*House.tile,playerZ:3.12*House.tile), "Waleed must not catch the player diagonally through a wall")
check(House.walkableBetween(3.5*House.tile,4.5*House.tile,3.5*House.tile,6.5*House.tile,radius:0.18), "An open doorway should allow a direct chase")
check(!House.walkableBetween(4.5*House.tile,4.5*House.tile,4.5*House.tile,6.5*House.tile,radius:0.18), "A blocked doorway approach must use the patrol grid")
let search = House.searchCells(near:House.spawn)
check(search.count == 3 && Set(search).count == 3, "Search should cover distinct reachable cells")
check(search.allSatisfy { (2...4).contains(House.path(from:House.spawn,to:$0).count) }, "Search should stay around the last known position")
print("House validation passed: all objectives reachable, patrol connected, walls block movement and sight.")
