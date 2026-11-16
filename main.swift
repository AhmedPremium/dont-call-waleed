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
print("House validation passed: all objectives reachable, patrol connected, walls block movement and sight.")
