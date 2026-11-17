import Foundation

struct Cell: Hashable { var x: Int; var z: Int }

struct House {
    static let tile: Float = 2.4
    private static let originalRows = [
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
    static let panel = Cell(x: 14, z: 14)
    static let exit = Cell(x: 7, z: 15)
    static let closets = [Cell(x: 1, z: 14), Cell(x: 1, z: 3), Cell(x: 15, z: 9), Cell(x: 24, z: 3), Cell(x: 24, z: 13)]
    let rows: [[Character]]
    let fuses: [Cell]
    let patrol: [Cell]
    static let fuseTableShift: Float = -0.59
    private let furniture: [Footprint]
    private let fuseCells: Set<Cell>

    private struct Footprint {
        let x: Float
        let z: Float
        let halfWidth: Float
        let halfDepth: Float

        init(_ cell:Cell,_ xOffset:Float,_ zOffset:Float,_ halfWidth:Float,_ halfDepth:Float) {
            x = (Float(cell.x)+0.5)*House.tile+xOffset
            z = (Float(cell.z)+0.5)*House.tile+zOffset
            self.halfWidth = halfWidth
            self.halfDepth = halfDepth
        }

        func blocks(_ x:Float,_ z:Float,_ radius:Float) -> Bool {
            abs(self.x-x) < halfWidth+radius && abs(self.z-z) < halfDepth+radius
        }
    }

    init(seed: UInt64 = UInt64.random(in:UInt64.min...UInt64.max)) {
        var state = seed
        func select(_ count: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(count))
        }

        var layout = Self.originalRows
        let wings = [1...4, 6...9, 11...15]
        for z in layout.indices {
            let room = wings.contains { $0.contains(z) }
            layout[z] += Array(repeating:room ? "." : "#",count:9)
            layout[z].append("#")
        }
        for band in wings {
            let doorway = band.lowerBound + select(band.count)
            layout[doorway][16] = "."
        }
        for z in [5, 10] {
            let doorway = 18 + select(6)
            layout[z][doorway] = "."
        }
        let alternatives = [
            [Cell(x:2,z:2), Cell(x:22,z:3), Cell(x:13,z:4)],
            [Cell(x:23,z:8), Cell(x:19,z:7), Cell(x:23,z:6)],
            [Cell(x:3,z:12), Cell(x:12,z:13), Cell(x:20,z:14)]
        ]
        rows = layout
        let selectedFuses = alternatives.map { $0[select($0.count)] }
        fuses = selectedFuses
        fuseCells = Set(selectedFuses)
        let kitchen = Cell(x:12,z:1)
        let counters = [-2,-1,1,2].map {
            Footprint(kitchen,Float($0)*1.18,-0.87,0.59,0.325)
        }
        let fuseTables = selectedFuses.map { Footprint($0,0,Self.fuseTableShift-0.18,0.46,0.32) }
        furniture = counters + fuseTables + [Footprint(kitchen,0,-0.93,0.52,0.195)]
        patrol = [Self.enemy,Cell(x:23,z:3),Cell(x:2,z:2),Cell(x:2,z:8),
                  Cell(x:21,z:8),Cell(x:23,z:13),Cell(x:14,z:14),Cell(x:3,z:13)]
    }
    var doorways: [(cell: Cell, rotated: Bool)] {
        var result = [(cell: Cell, rotated: Bool)]()
        for z in 1..<(rows.count-1) {
            for x in 1..<(rows[z].count-1) where rows[z][x] == "." {
                let horizontal = rows[z][x-1] == "." && rows[z][x+1] == "."
                let vertical = rows[z-1][x] == "." && rows[z+1][x] == "."
                if horizontal && rows[z-1][x] == "#" && rows[z+1][x] == "#" {
                    result.append((Cell(x:x,z:z),true))
                } else if vertical && rows[z][x-1] == "#" && rows[z][x+1] == "#" {
                    result.append((Cell(x:x,z:z),false))
                }
            }
        }
        return result
    }

    func open(_ c: Cell) -> Bool {
        c.z >= 0 && c.z < rows.count && c.x >= 0 && c.x < rows[c.z].count && rows[c.z][c.x] != "#"
    }
    static func cell(_ x: Float, _ z: Float) -> Cell { Cell(x:Int(floor(x/tile)),z:Int(floor(z/tile))) }
    func walkable(_ x: Float, _ z: Float, radius: Float = 0.25) -> Bool {
        guard [-radius,radius].allSatisfy({ dx in
            [-radius,radius].allSatisfy { dz in open(Self.cell(x+dx,z+dz)) }
        }) else { return false }
        return !furniture.contains { $0.blocks(x,z,radius) }
    }
    func path(from: Cell, to: Cell) -> [Cell] {
        guard open(from),open(to),from != to else { return [] }
        var queue = [from], seen: Set<Cell> = [from], previous: [Cell:Cell] = [:], index = 0
        while index < queue.count {
            let c = queue[index]; index += 1
            for n in [Cell(x:c.x+1,z:c.z),Cell(x:c.x-1,z:c.z),Cell(x:c.x,z:c.z+1),Cell(x:c.x,z:c.z-1)] where open(n) && !seen.contains(n) && clearStep(from:c,to:n) {
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
    private func clearStep(from cell:Cell,to next:Cell) -> Bool {
        guard cell.x == next.x else { return true }
        // The fuse table sits between its tile center and the next one to the north.
        return !fuseCells.contains(cell.z > next.z ? cell : next)
    }

    static func reachedWaypoint(_ remaining: Float) -> Bool { remaining <= 0.012 }

    func searchCells(near origin: Cell) -> [Cell] {
        var candidates = [Cell]()
        for dz in -3...3 {
            for dx in -3...3 where abs(dx)+abs(dz) >= 2 && abs(dx)+abs(dz) <= 3 {
                let candidate = Cell(x:origin.x+dx,z:origin.z+dz)
                let route = path(from:origin,to:candidate)
                if !route.isEmpty && route.count <= 4 { candidates.append(candidate) }
            }
        }
        return Array(candidates.shuffled().prefix(3))
    }

    func canCatch(enemyX: Float, enemyZ: Float, playerX: Float, playerZ: Float) -> Bool {
        let close = hypot(playerX-enemyX,playerZ-enemyZ) <= 1.30
        return close && walkableBetween(enemyX,enemyZ,playerX,playerZ,radius:0)
    }

    func walkableBetween(_ ax: Float,_ az: Float,_ bx: Float,_ bz: Float,radius: Float) -> Bool {
        let steps = max(1,Int(ceil(hypot(bx-ax,bz-az)/0.10)))
        for i in 0...steps {
            let t = Float(i)/Float(steps)
            if !walkable(ax+(bx-ax)*t,az+(bz-az)*t,radius:radius) { return false }
        }
        return true
    }

    func visible(_ ax:Float,_ az:Float,_ bx:Float,_ bz:Float) -> Bool {
        let steps = max(1,Int(ceil(hypot(bx-ax,bz-az)/0.10)))
        for i in 0...steps {
            let t = Float(i)/Float(steps)
            if !open(Self.cell(ax+(bx-ax)*t,az+(bz-az)*t)) { return false }
        }
        return true
    }
}

enum OpeningLayout {
    static let upperFloor: Float = 2.85
    static let stairEnd: Float = -5.6
    static let frontDoorZ: Float = -10.45
    static let bedside = (x: Float(-0.72), z: Float(3.65))

    static func walkable(x:Float,z:Float) -> Bool {
        guard z < 5.45 && z > frontDoorZ+0.18 else { return false }
        if z >= 0.22 {
            let onBed = x > -2.89 && x < -1.13 && z > 2.99
            return abs(x) < 3.06 && !onBed
        }
        if z >= stairEnd-0.17 { return abs(x) < 0.82 }
        return z > frontDoorZ+0.18 && abs(x) < 2.95
    }

    static func floorHeight(at z:Float) -> Float {
        upperFloor*min(1,max(0,(z-stairEnd)/(-stairEnd)))
    }

    static func canOpenDoor(x:Float,z:Float) -> Bool {
        abs(x) < 0.95 && z < frontDoorZ+1.27 && z >= frontDoorZ
    }
}
