import Foundation

struct Cell: Hashable { var x: Int; var z: Int }

enum House {
    static let tile: Float = 2.4
    static let rows = [
        "#################",
        "#.......#.......#",
        "#.......#.......#",
        "#...............#",
        "#.......#.......#",
        "###.#######.#####",
        "#.......#.......#",
        "#.......#.......#",
        "#...............#",
        "#.......#.......#",
        "###.#######.#####",
        "#.......#.......#",
        "#.......#.......#",
        "#...............#",
        "#.......#.......#",
        "#.......#.......#",
        "#################"
    ].map(Array.init)
    static let spawn = Cell(x: 2, z: 14)
    static let enemy = Cell(x: 14, z: 2)
    static let fuses = [Cell(x: 2, z: 2), Cell(x: 14, z: 7), Cell(x: 2, z: 7)]
    static let panel = Cell(x: 14, z: 14)
    static let exit = Cell(x: 7, z: 15)
    static let closets = [Cell(x: 1, z: 14), Cell(x: 1, z: 3), Cell(x: 15, z: 9)]
    static let patrol = [Cell(x:14,z:2),Cell(x:2,z:2),Cell(x:2,z:8),Cell(x:14,z:8),Cell(x:14,z:14),Cell(x:3,z:13)]
    static func open(_ c: Cell) -> Bool {
        c.z >= 0 && c.z < rows.count && c.x >= 0 && c.x < rows[c.z].count && rows[c.z][c.x] != "#"
    }
    static func cell(_ x: Float, _ z: Float) -> Cell { Cell(x:Int(floor(x/tile)),z:Int(floor(z/tile))) }
    static func walkable(_ x: Float, _ z: Float, radius: Float = 0.25) -> Bool {
        [-radius,radius].allSatisfy { dx in [-radius,radius].allSatisfy { dz in open(cell(x+dx,z+dz)) } }
    }
    static func path(from: Cell, to: Cell) -> [Cell] {
        guard open(from),open(to),from != to else { return [] }
        var queue = [from], seen: Set<Cell> = [from], previous: [Cell:Cell] = [:], index = 0
        while index < queue.count {
            let c = queue[index]; index += 1
            for n in [Cell(x:c.x+1,z:c.z),Cell(x:c.x-1,z:c.z),Cell(x:c.x,z:c.z+1),Cell(x:c.x,z:c.z-1)] where open(n) && !seen.contains(n) {
                seen.insert(n); previous[n] = c
                if n == to {
                    var result = [n], current = n
                    while let p = previous[current], p != from { result.append(p); current = p }
                    return result.reversed()
                }
                queue.append(n)
            }
        }
        return []
    }
    static func visible(_ ax:Float,_ az:Float,_ bx:Float,_ bz:Float) -> Bool {
        let steps = max(1,Int(hypot(bx-ax,bz-az)/0.2))
        for i in 0...steps {
            let t = Float(i)/Float(steps)
            if !open(cell(ax+(bx-ax)*t,az+(bz-az)*t)) { return false }
        }
        return true
    }
}
