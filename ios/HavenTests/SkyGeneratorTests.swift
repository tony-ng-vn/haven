import Foundation
import Testing
@testable import Haven

// The sky generator is a port of the web app's src/sky.ts. The public web card
// page will render the same person's constellation from the same seed, so the
// two implementations have to agree. These vectors were dumped from the
// TypeScript and are the contract between them: if a change here makes them
// fail, the change is wrong, or src/sky.ts moved and this must follow it.
//
// Doubles are compared to 1e-9 rather than exactly, because pow() is not
// guaranteed to round identically in the two runtimes. That is roughly a
// billionth of a pixel, so anything a person can see would fail this.

private let tolerance = 1e-9

private func expectClose(_ actual: Double, _ expected: Double, _ label: String) {
    #expect(abs(actual - expected) < tolerance, "\(label): got \(actual), want \(expected)")
}

// MARK: - Cross-language agreement

@Suite("Sky matches the web generator")
struct SkyCrossLanguageTests {
    @Test("a Convex-shaped user id")
    func userIdSeed() {
        let sky = SkyGenerator.build(seed: "user_2abcDEF123")

        #expect(sky.hues == (304, 89, 165))
        #expect(sky.majors.count == 7)

        let wantMajors: [(Double, Double, Double, Double, Double)] = [
            (235.39891170337796, 320.4532804884948, 1.9875956312054768, 304, 0.47005920647643507),
            (319.23596502281725, 83.40335263311863, 3.2235948532819747, 89, 0.9649363220669329),
            (168.97186608426273, 235.36024169307203, 1.8641928023425862, 165, 0.3800737315323204),
            (152.12313545681536, 150.5907592647709, 3.308014835370704, 304, 0.7052257873583585),
            (38.11913896724582, 77.19102088455111, 2.1699175021611152, 89, 0.6608353198971599),
            (191.05322508048266, 77.07249350743368, 1.7541159671498463, 165, 0.7025365261361003),
            (50.75784392096102, 326.4131235693581, 1.8322956213494763, 304, 0.30275094881653786),
        ]
        for (i, want) in wantMajors.enumerated() {
            expectClose(sky.majors[i].x, want.0, "major \(i) x")
            expectClose(sky.majors[i].y, want.1, "major \(i) y")
            expectClose(sky.majors[i].r, want.2, "major \(i) r")
            expectClose(sky.majors[i].hue, want.3, "major \(i) hue")
            expectClose(sky.majors[i].rvd, want.4, "major \(i) rvd")
        }

        #expect(sky.edges.map { [$0.0, $0.1] } == [[0, 2], [2, 3], [3, 5], [5, 1], [3, 4], [2, 6]])

        // The first and last minor bracket all 150 draws: if the stream drifted
        // anywhere in between, the last one moves.
        let first = sky.minors[0]
        expectClose(first.x, 9.658468097448349, "minor 0 x")
        expectClose(first.y, 210.45200988650322, "minor 0 y")
        expectClose(first.r, 1.4206857170464033, "minor 0 r")
        expectClose(first.hi, 0.5777898492640816, "minor 0 hi")
        expectClose(first.lo, 0.2777898492640816, "minor 0 lo")
        expectClose(first.dur, 4.674956691707484, "minor 0 dur")
        expectClose(first.delay, 2.702207720372826, "minor 0 delay")
        expectClose(first.rvd, 0.41310114273801446, "minor 0 rvd")

        let last = sky.minors[149]
        expectClose(last.x, 176.20741653442383, "minor 149 x")
        expectClose(last.y, 39.01709442958236, "minor 149 y")
        expectClose(last.r, 0.40913336599133754, "minor 149 r")
        expectClose(last.dur, 4.003498604660853, "minor 149 dur")
        expectClose(last.rvd, 0.6704064393416047, "minor 149 rvd")

        let featured = sky.minors.enumerated().filter { $0.element.featured }.map(\.offset)
        #expect(featured == [8, 34, 43, 46, 47, 49, 53, 66, 69, 71, 75, 84, 95, 100, 102, 109,
                             118, 121, 122, 131, 139, 149])

        expectClose(sky.giants[0].x, 300.3091885196045, "giant 0 x")
        expectClose(sky.giants[0].y, 248.51877446472645, "giant 0 y")
        expectClose(sky.giants[0].r, 1.9463399479165673, "giant 0 r")
        expectClose(sky.giants[0].rvd, 0.0286595665384084, "giant 0 rvd")

        // Flares go to the two widest majors, here indexes 3 and 1.
        expectClose(sky.flares[0].x, 152.12313545681536, "flare 0 x")
        expectClose(sky.flares[0].len, 29.77213351833634, "flare 0 len")
        expectClose(sky.flares[0].dur, 4.369560748338699, "flare 0 dur")
        expectClose(sky.flares[0].delay, 2.349030532874167, "flare 0 delay")
        expectClose(sky.flares[1].x, 319.23596502281725, "flare 1 x")
        expectClose(sky.flares[1].len, 29.01235367953777, "flare 1 len")

        expectClose(sky.shoot.x1, 80.48214886337519, "shoot x1")
        expectClose(sky.shoot.y1, 126.53690105304122, "shoot y1")
        expectClose(sky.shoot.x2, 46.48214886337519, "shoot x2")
        expectClose(sky.shoot.y2, 107.53690105304122, "shoot y2")
        expectClose(sky.shoot.delay, 6.781750701367855, "shoot delay")
    }

    @Test("a seed that yields eight majors, not seven")
    func eightMajorSeed() {
        let sky = SkyGenerator.build(seed: "jd7h1k2m9n0p")

        #expect(sky.hues == (6, 203, 156))
        #expect(sky.majors.count == 8)
        expectClose(sky.majors[0].x, 319.3977517802268, "major 0 x")
        expectClose(sky.majors[7].x, 262.89981048181653, "major 7 x")
        expectClose(sky.majors[7].r, 1.650065477960743, "major 7 r")
        #expect(sky.edges.map { [$0.0, $0.1] }
            == [[0, 6], [6, 7], [7, 1], [1, 4], [0, 5], [5, 3], [3, 2]])
        expectClose(sky.shoot.delay, 3.9938202369958162, "shoot delay")
        let featured = sky.minors.enumerated().filter { $0.element.featured }.map(\.offset)
        #expect(featured == [3, 4, 16, 19, 20, 23, 33, 37, 66, 68, 69, 76, 79, 90, 95, 97,
                             106, 121, 123, 137, 141, 146])
    }

    @Test("a one-character seed, and a hue that lands on zero")
    func shortSeed() {
        let sky = SkyGenerator.build(seed: "x")

        // The middle hue is 0 here, which a signed-shift bug would turn negative.
        #expect(sky.hues == (135, 0, 355))
        #expect(sky.majors[1].hue == 0)
        expectClose(sky.majors[0].x, 339.9937129560858, "major 0 x")
        expectClose(sky.majors[6].r, 3.386231421958655, "major 6 r")
        #expect(sky.edges.map { [$0.0, $0.1] } == [[0, 1], [1, 4], [4, 6], [4, 3], [3, 5], [5, 2]])
    }

    @Test("an empty seed still mints a whole sky")
    func emptySeed() {
        let sky = SkyGenerator.build(seed: "")

        #expect(sky.hues == (61, 14, 343))
        #expect(sky.majors.count == 8)
        expectClose(sky.majors[0].x, 178.03597830608487, "major 0 x")
        expectClose(sky.majors[0].r, 3.2375908725662157, "major 0 r")
        #expect(sky.edges.map { [$0.0, $0.1] }
            == [[0, 7], [0, 3], [0, 6], [6, 5], [5, 1], [6, 2], [7, 4]])
    }

    @Test("a seed with an accent and an astral-plane emoji")
    func unicodeSeed() {
        // The hash runs over UTF-16 code units, so the emoji contributes a
        // surrogate pair. Hashing Unicode scalars instead would diverge here.
        let sky = SkyGenerator.build(seed: "Zo\u{EB} \u{1F30C}")

        #expect(sky.hues == (29, 68, 313))
        #expect(sky.majors.count == 7)
        expectClose(sky.majors[0].x, 89.23560034297407, "major 0 x")
        expectClose(sky.majors[0].r, 3.1452840087236833, "major 0 r")
        #expect(sky.edges.map { [$0.0, $0.1] } == [[0, 4], [4, 2], [2, 3], [4, 1], [2, 5], [3, 6]])
    }
}

// MARK: - Properties that must hold for any person

@Suite("Sky invariants")
struct SkyInvariantTests {
    private let seeds = ["user_2abcDEF123", "jd7h1k2m9n0p", "x", "", "Zo\u{EB} \u{1F30C}",
                         "aaaaaaaa", "user_zzzz9999", "n"]

    @Test("the same seed always mints the same sky")
    func deterministic() {
        for seed in seeds {
            #expect(SkyGenerator.build(seed: seed) == SkyGenerator.build(seed: seed),
                    "seed \(seed) was not stable")
        }
    }

    @Test("different seeds mint different figures")
    func distinct() {
        let figures = seeds.map { seed in
            SkyGenerator.build(seed: seed).majors.map { [$0.x, $0.y] }
        }
        for i in figures.indices {
            for j in (i + 1)..<figures.count {
                #expect(figures[i] != figures[j], "seeds \(seeds[i]) and \(seeds[j]) collided")
            }
        }
    }

    @Test("the figure is a connected tree with no cycles")
    func edgesFormTree() {
        for seed in seeds {
            let sky = SkyGenerator.build(seed: seed)
            let n = sky.majors.count
            #expect(sky.edges.count == n - 1, "seed \(seed): \(sky.edges.count) edges for \(n) stars")

            var reached = Set([0])
            for edge in sky.edges {
                #expect((0..<n).contains(edge.0) && (0..<n).contains(edge.1),
                        "seed \(seed): edge \(edge) out of range")
                #expect(edge.0 != edge.1, "seed \(seed): self edge at \(edge.0)")
                // Prim's grows from the tree outward, so the first endpoint is
                // always already reached and the second is always new.
                #expect(reached.contains(edge.0), "seed \(seed): edge \(edge) starts outside the tree")
                #expect(!reached.contains(edge.1), "seed \(seed): edge \(edge) revisits a star")
                reached.insert(edge.1)
            }
            #expect(reached.count == n, "seed \(seed): figure is not connected")
        }
    }

    @Test("majors never crowd each other and stay in the upper sky")
    func majorsPlacedWell() {
        for seed in seeds {
            let sky = SkyGenerator.build(seed: seed)
            #expect((7...8).contains(sky.majors.count), "seed \(seed): \(sky.majors.count) majors")

            for major in sky.majors {
                #expect(major.x >= SkyGenerator.pad)
                #expect(major.x <= SkyGenerator.width - SkyGenerator.pad)
                #expect(major.y >= SkyGenerator.pad)
                // Placement caps y at 62% of the height so the name owns the
                // bottom of the card.
                #expect(major.y <= SkyGenerator.height * 0.62)
            }

            for i in sky.majors.indices {
                for j in (i + 1)..<sky.majors.count {
                    let dx = sky.majors[i].x - sky.majors[j].x
                    let dy = sky.majors[i].y - sky.majors[j].y
                    #expect(sqrt(dx * dx + dy * dy) >= 68,
                            "seed \(seed): majors \(i) and \(j) crowd each other")
                }
            }
        }
    }

    @Test("the minor field has the right shape")
    func minorsShape() {
        for seed in seeds {
            let sky = SkyGenerator.build(seed: seed)
            #expect(sky.minors.count == 150)
            #expect(sky.minors.filter(\.featured).count == 22)
            #expect(sky.giants.count == 5)
            #expect(sky.flares.count == 2)
            #expect(sky.nebulae.count == 3)

            for minor in sky.minors {
                #expect(minor.hi > minor.lo, "resting opacity must sit above the twinkle low")
                #expect(minor.lo >= 0.08, "twinkle low is floored so no star vanishes")
                #expect(minor.r > 0)
                #expect(minor.dur > 0)
                #expect((0...1).contains(minor.rvd))
            }
        }
    }

    @Test("hues stay inside the colour wheel")
    func huesInRange() {
        for seed in seeds {
            let hues = SkyGenerator.hues(seed: seed)
            for hue in [hues.0, hues.1, hues.2] {
                #expect(hue >= 0, "seed \(seed): negative hue \(hue)")
                #expect(hue < 360, "seed \(seed): hue \(hue) past the wheel")
            }
        }
    }

    @Test("spanning tree handles degenerate inputs")
    func spanningTreeEdgeCases() {
        #expect(SkyGenerator.spanningTree([]).isEmpty)
        #expect(SkyGenerator.spanningTree([(x: 1, y: 1)]).isEmpty)
        let pair = SkyGenerator.spanningTree([(x: 0, y: 0), (x: 5, y: 5)])
        #expect(pair.map { [$0.0, $0.1] } == [[0, 1]])
    }
}
