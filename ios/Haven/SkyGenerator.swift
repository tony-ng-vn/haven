import Foundation

// Every person's card is a unique patch of space, minted deterministically from
// their identity. Same person, same sky, forever.
//
// This is a port of the web app's src/sky.ts, and it has to stay a port: the
// public web card page renders the same person's constellation from the same
// seed, so the two implementations must agree bit for bit. SkyGeneratorTests
// asserts that against vectors dumped from the TypeScript.
//
// One deliberate difference from the web signature: the seed is the Convex user
// id, not a display name. Names collide, and a person editing their name must
// not get a different sky.

// MARK: - Shapes

struct SkyStar: Equatable {
    var x: Double
    var y: Double
    var r: Double
    /// Resting opacity.
    var hi: Double
    /// Twinkle-low opacity.
    var lo: Double
    /// Twinkle duration, seconds.
    var dur: Double
    var delay: Double
    /// 0..1 stagger seed deciding when this star ignites during a reveal.
    var rvd: Double
    /// Minors only. A seeded few keep an individual twinkle; the rest render
    /// static under one group shimmer, so the sky animates ~30 nodes, not ~150.
    var featured: Bool = false
}

struct SkyMajor: Equatable {
    var x: Double
    var y: Double
    var r: Double
    var hue: Double
    var hi: Double
    var lo: Double
    var dur: Double
    var delay: Double
    var rvd: Double
}

struct SkyNebula: Equatable {
    var cx: Double
    var cy: Double
    var rx: Double
    var ry: Double
    var hue: Double
    var alpha: Double
}

struct SkyFlare: Equatable {
    /// Which of `Sky.majors` this flare belongs to. The renderer needs it: a
    /// flare is the signature of a very bright star, so it has to fade with
    /// the star rather than blaze out of an unlit dot.
    var major: Int
    var x: Double
    var y: Double
    var len: Double
    var dur: Double
    var delay: Double
}

struct SkyShootingStar: Equatable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var delay: Double
}

struct Sky: Equatable {
    var width: Double
    var height: Double
    var pad: Double
    var hues: (Double, Double, Double)
    var nebulae: [SkyNebula]
    var minors: [SkyStar]
    var giants: [SkyMajor]
    /// The figure. Connected by `edges`, and the stars the card lights per field.
    var majors: [SkyMajor]
    /// Index pairs into `majors`.
    var edges: [(Int, Int)]
    var flares: [SkyFlare]
    var shoot: SkyShootingStar

    static func == (a: Sky, b: Sky) -> Bool {
        a.width == b.width && a.height == b.height && a.pad == b.pad
            && a.hues == b.hues && a.nebulae == b.nebulae && a.minors == b.minors
            && a.giants == b.giants && a.majors == b.majors
            && a.edges.elementsEqual(b.edges, by: ==)
            && a.flares == b.flares && a.shoot == b.shoot
    }
}

// MARK: - Generator

enum SkyGenerator {
    static let width: Double = 384
    static let height: Double = 560
    static let pad: Double = 34

    private static let minSeparation: Double = 68
    private static let minorCount = 150
    /// Fixed so every sky animates the same handful of minors.
    private static let featuredMinors = 22

    /// FNV-1a over UTF-16 code units, matching JavaScript's charCodeAt.
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for unit in s.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return h
    }

    static func hues(seed: String) -> (Double, Double, Double) {
        let h = hash(seed)
        // Unsigned shifts throughout: a signed shift on a large hash yields
        // negative hues.
        return (Double(h % 360), Double((h >> 9) % 360), Double((h >> 18) % 360))
    }

    /// mulberry32. Tiny, fast, deterministic. UInt32 with wrapping operators
    /// reproduces JavaScript's Math.imul and `>>>` exactly.
    struct Random {
        private var a: UInt32

        init(seed: UInt32) {
            a = seed
        }

        mutating func next() -> Double {
            a = a &+ 0x6D2B_79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = ((t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t)
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// Rejection-sampled placement: nothing crowds, nothing clips, and the
    /// figure keeps to the upper sky so the name owns the bottom of the card.
    private static func placeMajors(_ rand: inout Random, count: Int) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        var tries = 0
        while points.count < count && tries < 600 {
            tries += 1
            let x = pad + rand.next() * (width - pad * 2)
            let y = pad + rand.next() * (height * 0.62 - pad)
            let crowded = points.contains { p in
                let dx = p.x - x
                let dy = p.y - y
                return dx * dx + dy * dy < minSeparation * minSeparation
            }
            if !crowded { points.append((x: x, y: y)) }
        }
        return points
    }

    /// Prim's minimum spanning tree: each star joins its nearest branch, which
    /// is why real star charts look calm instead of criss-crossed.
    static func spanningTree(_ points: [(x: Double, y: Double)]) -> [(Int, Int)] {
        guard !points.isEmpty else { return [] }
        var inTree = [0]
        var edges: [(Int, Int)] = []
        while inTree.count < points.count {
            var best: (i: Int, j: Int, d: Double)?
            for i in inTree {
                for j in 0..<points.count {
                    if inTree.contains(j) { continue }
                    let dx = points[i].x - points[j].x
                    let dy = points[i].y - points[j].y
                    let d = dx * dx + dy * dy
                    // Strictly less-than keeps ties with the first candidate
                    // found, matching the JavaScript iteration order.
                    if best == nil || d < best!.d { best = (i: i, j: j, d: d) }
                }
            }
            guard let picked = best else { break }
            edges.append((picked.i, picked.j))
            inTree.append(picked.j)
        }
        return edges
    }

    static func build(seed: String) -> Sky {
        var rand = Random(seed: hash(seed))
        let hue = hues(seed: seed)
        let hueAt: (Int) -> Double = { i in
            switch i % 3 {
            case 0: return hue.0
            case 1: return hue.1
            default: return hue.2
            }
        }

        let nebulae = [
            SkyNebula(cx: width * 0.35, cy: height * 0.25, rx: width * 0.75, ry: height * 0.42,
                      hue: hue.0, alpha: 0.18),
            SkyNebula(cx: width * 0.75, cy: height * 0.5, rx: width * 0.65, ry: height * 0.36,
                      hue: hue.1, alpha: 0.15),
            SkyNebula(cx: width * 0.4, cy: height * 0.7, rx: width * 0.6, ry: height * 0.3,
                      hue: hue.2, alpha: 0.13),
        ]

        // Depth: many faint stars on a power law. The difference between a
        // diagram and a sky.
        var minors: [SkyStar] = []
        minors.reserveCapacity(minorCount)
        for _ in 0..<minorCount {
            let hi = 0.25 + rand.next() * 0.55
            minors.append(SkyStar(
                x: rand.next() * width,
                y: rand.next() * height,
                r: 0.4 + pow(rand.next(), 2.6) * 1.4,
                hi: hi,
                lo: max(0.08, hi - 0.3),
                dur: 2.6 + rand.next() * 4.5,
                delay: rand.next() * 6,
                rvd: rand.next()
            ))
        }

        // A few colored giants, like a telescope frame.
        var giants: [SkyMajor] = []
        for i in 0..<5 {
            giants.append(SkyMajor(
                x: pad + rand.next() * (width - pad * 2),
                y: pad + rand.next() * (height * 0.8),
                r: 1.2 + rand.next(),
                hue: hueAt(i),
                hi: 0.9,
                lo: 0.5,
                dur: 3 + rand.next() * 3,
                delay: rand.next() * 4,
                rvd: rand.next()
            ))
        }

        // The count is drawn before placement, matching the argument evaluation
        // order in the TypeScript. Moving it shifts every value after it.
        let majorCount = 7 + Int(floor(rand.next() * 2))
        let placed = placeMajors(&rand, count: majorCount)
        let edges = spanningTree(placed)
        var majors: [SkyMajor] = []
        for (i, p) in placed.enumerated() {
            majors.append(SkyMajor(
                x: p.x,
                y: p.y,
                r: 1.5 + rand.next() * 1.9,
                hue: hueAt(i),
                hi: 1,
                lo: 0.62,
                dur: 3 + rand.next() * 3.4,
                delay: rand.next() * 5,
                rvd: rand.next()
            ))
        }

        // The two brightest stars in the figure earn diffraction flares.
        // Sorted by radius descending, ties broken by index, which is what a
        // stable JavaScript sort gives.
        let brightest = majors.enumerated()
            .sorted { a, b in
                a.element.r == b.element.r ? a.offset < b.offset : a.element.r > b.element.r
            }
            .prefix(2)
        var flares: [SkyFlare] = []
        for entry in brightest {
            flares.append(SkyFlare(
                major: entry.offset,
                x: entry.element.x,
                y: entry.element.y,
                len: entry.element.r * 9,
                dur: 4 + rand.next() * 3,
                delay: rand.next() * 4
            ))
        }

        let sx = 40 + rand.next() * 160
        let sy = 30 + rand.next() * 120
        let shoot = SkyShootingStar(x1: sx, y1: sy, x2: sx - 34, y2: sy - 19,
                                   delay: 3 + rand.next() * 8)

        // Featured minors are picked LAST, after every other draw, so adding
        // this flag shifted no earlier value and no figure moved. Partial
        // Fisher-Yates over the same seeded stream keeps the pick stable per
        // person.
        var order = Array(0..<minors.count)
        let featureCount = min(featuredMinors, order.count)
        for i in 0..<featureCount {
            let j = i + Int(floor(rand.next() * Double(order.count - i)))
            order.swapAt(i, j)
            minors[order[i]].featured = true
        }

        return Sky(width: width, height: height, pad: pad, hues: hue, nebulae: nebulae,
                   minors: minors, giants: giants, majors: majors, edges: edges,
                   flares: flares, shoot: shoot)
    }
}
