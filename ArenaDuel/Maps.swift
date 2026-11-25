//
//  Maps.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import AppKit

struct MapBox {
    let x: Float, z: Float, w: Float, h: Float, l: Float     // h is the height of the TOP of the block
    let color: NSColor
    var base: Float = 0        // the bottom of the block. 0 = on the floor. A higher base makes a bridge you can walk under
    var solid = true           // false = just a painted marking on the floor
}

struct ArenaMap {
    let name: String
    let half: Float          // the arena is (2 x half) wide and long
    let accent: NSColor      // wall trim and spawn pads
    let sky: NSColor         // sky and distance haze
    let boxes: [MapBox]

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    enum Axis { case x, z }

    /// A staircase of boxes. It starts at (x, z) at the LOW end and climbs in direction `dir` (+1 or -1)
    /// along `along`. The default steps are 0.375 high, so you walk up without jumping.
    static func stairs(x: Float, z: Float, along: Axis, dir: Float, steps: Int,
                       tread: Float = 0.7, rise: Float = 0.375, width: Float = 2.4,
                       color: NSColor) -> [MapBox] {
        (0..<steps).map { i in
            let d = dir * (Float(i) + 0.5) * tread
            let h = Float(i + 1) * rise
            return along == .x
                ? MapBox(x: x + d, z: z, w: tread, h: h, l: width, color: color)
                : MapBox(x: x, z: z + d, w: width, h: h, l: tread, color: color)
        }
    }

    /// A thin walkway or bridge. You can walk on top of it and underneath it.
    static func platform(x: Float, z: Float, w: Float, l: Float, top: Float,
                         thick: Float = 0.4, color: NSColor) -> MapBox {
        MapBox(x: x, z: z, w: w, h: top, l: l, color: color, base: top - thick)
    }

    static func crate(_ x: Float, _ z: Float, _ size: Float, h: Float, color: NSColor) -> MapBox {
        MapBox(x: x, z: z, w: size, h: h, l: size, color: color)
    }

    static func stripe(x: Float, z: Float, w: Float, l: Float, color: NSColor) -> MapBox {
        MapBox(x: x, z: z, w: w, h: 0.02, l: l, color: color, solid: false)
    }

    // Palette
    static let blue = rgb(0.38, 0.62, 1.0)
    static let orange = rgb(1.0, 0.66, 0.32)
    static let mint = rgb(0.42, 0.85, 0.70)
    static let coral = rgb(1.0, 0.55, 0.58)
    static let lav = rgb(0.70, 0.55, 0.98)
    static let sand = rgb(1.0, 0.82, 0.5)
    static let stair = rgb(0.9, 0.93, 0.98)
    static let line = rgb(0.80, 0.86, 0.96)

    // Spawns are at x = -(half - 5) and x = +(half - 5), z = 0. Keep them clear.
    // You can jump about 1.5 high, so a block up to ~2 high can be climbed using a 1.0 crate as a step.
    static let all: [ArenaMap] = [
        ArenaMap(name: "Crossfire", half: 20, accent: rgb(0.25, 0.55, 0.95), sky: rgb(0.62, 0.82, 1.0),
                 boxes: crossfire()),
        ArenaMap(name: "Atrium", half: 22, accent: rgb(0.62, 0.45, 0.95), sky: rgb(0.80, 0.74, 0.98),
                 boxes: atrium()),
        ArenaMap(name: "Long Range", half: 30, accent: rgb(0.28, 0.76, 0.56), sky: rgb(0.70, 0.92, 0.85),
                 boxes: longRange()),
        ArenaMap(name: "Rooftops", half: 26, accent: rgb(1.0, 0.6, 0.25), sky: rgb(1.0, 0.86, 0.72),
                 boxes: rooftops()),
        ArenaMap(name: "Warehouse", half: 24, accent: rgb(0.95, 0.75, 0.2), sky: rgb(0.93, 0.90, 0.78),
                 boxes: warehouse()),
    ]

    // MARK: Crossfire: a central building you climb from both sides, towers by the spawns

    static func crossfire() -> [MapBox] {
        var b: [MapBox] = []
        b.append(MapBox(x: 0, z: 0, w: 6, h: 3.0, l: 6, color: blue))                      // central building
        b += stairs(x: 0, z: 8.6, along: .z, dir: -1, steps: 8, color: stair)
        b += stairs(x: 0, z: -8.6, along: .z, dir: 1, steps: 8, color: stair)
        b.append(MapBox(x: 0, z: 0, w: 2.4, h: 4.0, l: 0.6, color: coral, base: 3.0))      // rooftop cover
        for sx in [Float(-1), Float(1)] {
            for sz in [Float(-1), Float(1)] {
                b.append(MapBox(x: sx * 9, z: sz * 8, w: 3, h: 1.5, l: 3, color: orange))   // flank blocks
                b.append(crate(sx * 9, sz * 5.7, 1.4, h: 0.9, color: sand))
                b.append(MapBox(x: sx * 15, z: sz * 12, w: 2, h: 2, l: 2, color: coral))    // corner cover
            }
            b.append(MapBox(x: sx * 12, z: 0, w: 3, h: 2.5, l: 3, color: mint))             // towers by the spawns
            b.append(crate(sx * 9.4, 0, 1.6, h: 1.0, color: sand))
        }
        b.append(MapBox(x: 0, z: 13, w: 10, h: 1.2, l: 1, color: lav))                      // low walls
        b.append(MapBox(x: 0, z: -13, w: 10, h: 1.2, l: 1, color: lav))
        b.append(stripe(x: 0, z: 0, w: 38, l: 0.5, color: line))
        b.append(stripe(x: 0, z: 0, w: 0.5, l: 38, color: line))
        return b
    }

    // MARK: Atrium: tall pillars, a centre wall, and two catwalks you can walk on and under

    static func atrium() -> [MapBox] {
        var b: [MapBox] = []
        for sx in [Float(-1), Float(1)] {
            for sz in [Float(-1), Float(1)] {
                b.append(MapBox(x: sx * 7, z: sz * 7, w: 2, h: 4.5, l: 2, color: lav))       // tall pillars
                b.append(MapBox(x: sx * 12, z: sz * 4.5, w: 3, h: 2.0, l: 3, color: mint))   // side bunkers
                b.append(crate(sx * 12, sz * 7.2, 1.6, h: 1.0, color: sand))
            }
        }
        b.append(MapBox(x: 0, z: 0, w: 1, h: 2.5, l: 10, color: mint))                       // centre wall
        b.append(crate(1.4, 3.5, 1.4, h: 1.0, color: sand))
        b.append(crate(-1.4, -3.5, 1.4, h: 1.0, color: sand))
        for sz in [Float(-1), Float(1)] {                                                    // catwalks
            b.append(platform(x: 0, z: sz * 15, w: 16, l: 3, top: 3.0, color: stair))
            b += stairs(x: -13.6, z: sz * 15, along: .x, dir: 1, steps: 8, color: stair)
            b += stairs(x: 13.6, z: sz * 15, along: .x, dir: -1, steps: 8, color: stair)
            b.append(crate(-4, sz * 15, 2, h: 1.5, color: coral))                            // cover underneath
            b.append(crate(4, sz * 15, 2, h: 1.5, color: coral))
            b.append(MapBox(x: 0, z: sz * 16.6, w: 16, h: 3.9, l: 0.3, color: coral, base: 3.0))   // outer railing
        }
        b.append(stripe(x: 0, z: 0, w: 42, l: 0.5, color: line))
        b.append(stripe(x: 0, z: 0, w: 0.5, l: 42, color: line))
        return b
    }

    // MARK: Long Range: a big arena made for the sniper, with a tall central tower and four nests

    static func longRange() -> [MapBox] {
        var b: [MapBox] = []
        b.append(MapBox(x: 0, z: 0, w: 6, h: 4.0, l: 6, color: blue))                        // central tower
        b += stairs(x: 10.7, z: 0, along: .x, dir: -1, steps: 11, rise: 4.0 / 11, color: stair)
        b += stairs(x: -10.7, z: 0, along: .x, dir: 1, steps: 11, rise: 4.0 / 11, color: stair)
        b.append(MapBox(x: 0, z: 0, w: 2, h: 4.8, l: 0.5, color: coral, base: 4.0))          // roof cover
        for sx in [Float(-1), Float(1)] {
            for sz in [Float(-1), Float(1)] {
                b.append(MapBox(x: sx * 20, z: sz * 14, w: 5, h: 3.0, l: 5, color: lav))      // sniper nests
                b += stairs(x: sx * 20, z: sz * 5.9, along: .z, dir: sz, steps: 8, color: stair)
                b.append(MapBox(x: sx * 20, z: sz * 16.2, w: 5, h: 3.9, l: 0.4, color: coral, base: 3.0))
                b.append(MapBox(x: sx * 12, z: sz * 9, w: 8, h: 2.0, l: 1.5, color: coral))   // long cover walls
                b.append(MapBox(x: sx * 6, z: sz * 14, w: 5, h: 2.2, l: 2.4, color: orange))  // containers
                b.append(crate(sx * 5, sz * 5, 2, h: 1.5, color: sand))
                b.append(crate(sx * 14, sz * 21, 2, h: 1.0, color: sand))
            }
            b.append(MapBox(x: 0, z: sx * 22, w: 14, h: 1.5, l: 1, color: mint))             // low walls
        }
        b.append(stripe(x: 0, z: 0, w: 58, l: 0.5, color: line))
        b.append(stripe(x: 0, z: 0, w: 0.5, l: 58, color: line))
        return b
    }

    // MARK: Rooftops: four buildings joined by bridges. Walk across the roofs or underneath

    static func rooftops() -> [MapBox] {
        var b: [MapBox] = []
        let roofs: [(Float, Float)] = [(-9, 9), (9, 9), (-9, -9), (9, -9)]
        for (i, p) in roofs.enumerated() {
            b.append(MapBox(x: p.0, z: p.1, w: 8, h: 3.0, l: 8, color: i % 2 == 0 ? coral : mint))
            b.append(MapBox(x: p.0, z: p.1, w: 3, h: 4.0, l: 0.6, color: lav, base: 3.0))     // cover on the roof
        }
        b.append(platform(x: 0, z: 9, w: 10, l: 2.4, top: 3.0, color: stair))                // bridges
        b.append(platform(x: 0, z: -9, w: 10, l: 2.4, top: 3.0, color: stair))
        b.append(platform(x: -9, z: 0, w: 2.4, l: 10, top: 3.0, color: stair))
        b.append(platform(x: 9, z: 0, w: 2.4, l: 10, top: 3.0, color: stair))
        b += stairs(x: -18.6, z: 9, along: .x, dir: 1, steps: 8, color: stair)               // stairs up from the street
        b += stairs(x: 18.6, z: 9, along: .x, dir: -1, steps: 8, color: stair)
        b += stairs(x: -18.6, z: -9, along: .x, dir: 1, steps: 8, color: stair)
        b += stairs(x: 18.6, z: -9, along: .x, dir: -1, steps: 8, color: stair)
        b.append(MapBox(x: 0, z: 0, w: 3, h: 2.2, l: 3, color: sand))                        // centre plaza
        for sx in [Float(-1), Float(1)] {
            for sz in [Float(-1), Float(1)] {
                b.append(crate(sx * 3.5, sz * 3.5, 1.8, h: 1.5, color: orange))
            }
            b.append(MapBox(x: 0, z: sx * 16, w: 8, h: 1.4, l: 1, color: lav))               // street cover
            b.append(MapBox(x: sx * 15, z: 0, w: 1, h: 1.4, l: 6, color: lav))
        }
        b.append(stripe(x: 0, z: 0, w: 50, l: 0.5, color: line))
        b.append(stripe(x: 0, z: 0, w: 0.5, l: 50, color: line))
        return b
    }

    // MARK: Warehouse: partition walls, shelves, and mezzanine walkways along the sides

    static func warehouse() -> [MapBox] {
        var b: [MapBox] = []
        for sz in [Float(-1), Float(1)] {
            b.append(MapBox(x: -9.5, z: sz * 7, w: 13, h: 3.5, l: 1, color: stair))          // partition walls with a doorway
            b.append(MapBox(x: 9.5, z: sz * 7, w: 13, h: 3.5, l: 1, color: stair))
            b.append(platform(x: 0, z: sz * 16, w: 20, l: 4, top: 3.2, color: stair))        // mezzanines
            b += stairs(x: -16.3, z: sz * 16, along: .x, dir: 1, steps: 9, rise: 3.2 / 9, color: stair)
            b += stairs(x: 16.3, z: sz * 16, along: .x, dir: -1, steps: 9, rise: 3.2 / 9, color: stair)
            b.append(MapBox(x: 0, z: sz * 18.1, w: 20, h: 4.1, l: 0.3, color: coral, base: 3.2))   // railing
            b.append(MapBox(x: -5, z: sz * 16, w: 4, h: 1.6, l: 1.2, color: orange))         // shelves underneath
            b.append(MapBox(x: 5, z: sz * 16, w: 4, h: 1.6, l: 1.2, color: orange))
            b.append(crate(sz * 3.5, 3.5 * sz, 1.8, h: 1.2, color: sand))                    // crates in the corridor
            b.append(crate(sz * 12, 11, 2, h: 1.6, color: sand))                             // outer lane crates
            b.append(crate(sz * 12, -11, 2, h: 1.6, color: sand))
        }
        b.append(MapBox(x: -9, z: 0, w: 6, h: 1.8, l: 1.2, color: orange))                   // shelves in the corridor
        b.append(MapBox(x: 9, z: 0, w: 6, h: 1.8, l: 1.2, color: orange))
        b.append(stripe(x: 0, z: 0, w: 46, l: 0.5, color: line))
        return b
    }
}
