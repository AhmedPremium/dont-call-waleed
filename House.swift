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
    static let foyerEntrance = Cell(x:0,z:13)
    static let sunroomWindow = Cell(x:14,z:11)
    static let panel = Cell(x: 14, z: 14)
    static let fridgeStop = Cell(x:12,z:1)
    static let loungeTV = Cell(x:6,z:6)
    static let sofaStop = Cell(x:6,z:7)
    static let laundryWasher = Cell(x:6,z:11)
    static let studyShelves = Cell(x:14,z:6)
    static let listeningStop = Cell(x:8,z:8)
    static let exit = Cell(x: 7, z: 15)
    static let closets = [Cell(x: 1, z: 14), Cell(x: 1, z: 3), Cell(x: 15, z: 9)]
    private static let cupboardGroups = [
        [Cell(x:2,z:2), Cell(x:5,z:3), Cell(x:13,z:4)],
        [Cell(x:2,z:7), Cell(x:13,z:8), Cell(x:14,z:7)],
        [Cell(x:3,z:12), Cell(x:12,z:13), Cell(x:10,z:14)]
    ]
    static let cupboards = cupboardGroups.flatMap { $0 }
    static let cupboardOffset: Float = -0.78
    static let cupboardWidth: Float = 1.04
    static let cupboardDepth: Float = 0.46
    let rows: [[Character]]
    let fuses: [Cell]
    let patrol: [Cell]
    private let furniture: [Footprint]

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

        func blocksStep(x ax:Float,z az:Float,toX bx:Float,z bz:Float,radius:Float) -> Bool {
            let nearestX = min(max(x,min(ax,bx)),max(ax,bx))
            let nearestZ = min(max(z,min(az,bz)),max(az,bz))
            return blocks(nearestX,nearestZ,radius)
        }
    }

    init(seed: UInt64 = UInt64.random(in:UInt64.min...UInt64.max)) {
        var state = seed
        func select(_ count: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(count))
        }

        var layout = Self.originalRows
        layout[Self.foyerEntrance.z][Self.foyerEntrance.x] = "."
        // Shift the utility doors within each room while preserving the floor plan.
        for wall in [5,10] {
            layout[wall][3] = "#"
            layout[wall][11] = "#"
            layout[wall][3+select(2)] = "."
            layout[wall][11+select(2)] = "."
        }
        rows = layout
        fuses = Self.cupboardGroups.map { $0[select($0.count)] }
        let kitchen = Cell(x:12,z:1)
        let counters = [-2,-1,1,2].map {
            Footprint(kitchen,Float($0)*1.18,-0.87,0.59,0.325)
        }
        let cabinets = Self.cupboards.map {
            Footprint($0,0,Self.cupboardOffset,Self.cupboardWidth/2,Self.cupboardDepth/2)
        }
        furniture = counters + cabinets + [
            Footprint(kitchen,0,-0.93,0.52,0.195),
            Footprint(Self.loungeTV,0,-0.79,1.07,0.305),
            Footprint(Self.sofaStop,0,0.73,1.29,0.455),
            Footprint(Self.laundryWasher,0,-0.88,0.60,0.24),
            Footprint(Self.studyShelves,0,-0.92,0.89,0.215)
        ]
        patrol = [Self.enemy,Self.fridgeStop,Cell(x:2,z:2),Self.sofaStop,
                  Self.listeningStop,Cell(x:14,z:14),Cell(x:3,z:13)]
    }
    func reshuffled() -> House {
        var next = House()
        while next.rows == rows && next.fuses == fuses { next = House() }
        return next
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
        let x = (Float(cell.x)+0.5)*Self.tile, z = (Float(cell.z)+0.5)*Self.tile
        let nextX = (Float(next.x)+0.5)*Self.tile, nextZ = (Float(next.z)+0.5)*Self.tile
        return !furniture.contains { $0.blocksStep(x:x,z:z,toX:nextX,z:nextZ,radius:0.18) }
    }

    static func canNotice(range:Float,forward:Float,flashlight:Bool,crouched:Bool) -> Bool {
        guard !crouched, range < (flashlight ? 8.4 : 5.8) else { return false }
        return range < 1.55 || forward >= range*0.63
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
    static let portalLocalZ: Float = -8.02
    static let portalWorldZ = (Float(House.foyerEntrance.z)+0.5)*House.tile
    static let worldX: Float = -3.20
    static let worldZ = portalWorldZ-portalLocalZ
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

    static func walkableInHouse(_ house:House,x:Float,z:Float,radius:Float = 0.25) -> Bool {
        if abs(x) < 0.39 && abs(z-portalWorldZ) < 0.92 { return true }
        if x >= 0 { return house.walkable(x,z,radius:radius) }
        return walkable(x:x-worldX,z:z-worldZ)
    }

    static func heightInHouse(x:Float,z:Float) -> Float {
        x < 0 ? floorHeight(at:z-worldZ) : 0
    }

    static func floorHeight(at z:Float) -> Float {
        upperFloor*min(1,max(0,(z-stairEnd)/(-stairEnd)))
    }

    static func canOpenDoor(x:Float,z:Float) -> Bool {
        abs(x) < 0.95 && z < frontDoorZ+1.27 && z >= frontDoorZ
    }
}

enum EscapeSequence {
    enum Beat: Int, CaseIterable { case approach, stepOut, doorShuts, knocks, call, blackout, results }

    // Times also define the intervals used by the first-person camera moves.
    static let cues: [Float] = [0,1.0,3.65,4.90,6.65,9.35,10.15]

    static func beat(at elapsed:Float) -> Beat {
        Beat.allCases.last { elapsed >= cues[$0.rawValue] } ?? .approach
    }
}

// Uses the game's clock so reading or pausing cannot skip a call cue.
struct BreakerEncounter {
    enum Stage: Equatable {
        case inactive, flicker(started:Float), ringing(until:Float)
        case connected(knockAt:Float, clueAt:Float, knocked:Bool), finished
    }
    enum Cue: Equatable { case ring, knock, clue, missed }

    private(set) var stage = Stage.inactive

    var isActive: Bool {
        switch stage {
        case .inactive, .finished: false
        default: true
        }
    }

    mutating func start(at time:Float) {
        guard stage == .inactive else { return }
        stage = .flicker(started:time)
    }

    mutating func answer(at time:Float) -> Bool {
        guard case .ringing(let until) = stage, time < until else { return false }
        stage = .connected(knockAt:time+2.8,clueAt:time+5.1,knocked:false)
        return true
    }

    mutating func hangUp() -> Bool {
        guard case .connected = stage else { return false }
        stage = .finished
        return true
    }

    func isLit(at time:Float) -> Bool {
        guard case .flicker(let started) = stage else { return true }
        switch time-started {
        case ..<0.20, 0.40..<0.63, 0.83..<1.07: return true
        default: return false
        }
    }

    mutating func advance(to time:Float) -> Cue? {
        switch stage {
        case .flicker(let started) where time >= started+1.35:
            stage = .ringing(until:time+11)
            return .ring
        case .ringing(let until) where time >= until:
            stage = .finished
            return .missed
        case .connected(let knockAt,let clueAt,false) where time >= knockAt:
            stage = .connected(knockAt:knockAt,clueAt:clueAt,knocked:true)
            return .knock
        case .connected(_,let clueAt,true) where time >= clueAt:
            stage = .finished
            return .clue
        default: return nil
        }
    }
}
