import SwiftUI
import GraphCore

/// Renders a settled-or-settling ForceSimulation. Deliberately thin: node/edge selection and
/// styling decisions that are pure computation (which edges draw, which nodes label) live in
/// GraphCore/NodeColor, not here -- this view's own job is just driving `tick()` and drawing.
struct GraphView: View {
    let graph: Graph
    let simulation: ForceSimulation

    private let nodesByID: [String: GraphNode]
    private let labelNodeIDs: Set<String>

    @State private var scale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    init(graph: Graph, simulation: ForceSimulation) {
        self.graph = graph
        self.simulation = simulation
        self.nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        self.labelNodeIDs = LabelBudget.selectedNodeIDs(nodes: graph.nodes)
    }

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                // The assembly animation IS the simulation settling (PLAN.md): once alpha
                // floors, tick() is already a no-op inside ForceSimulation, so there is no
                // need to gate this call on isSettled for correctness -- only to avoid
                // pointlessly calling it forever, which the guard below still does.
                if !simulation.isSettled {
                    simulation.tick()
                }
                draw(into: context, canvasSize: size)
            }
        }
        .background(Color.black)
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnifyGesture)
        .gesture(dragGesture)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 0.2), 6.0)
            }
            .onEnded { _ in
                committedScale = scale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func draw(into context: GraphicsContext, canvasSize: CGSize) {
        let positions = simulation.positions
        // While settling: no labels at all. Once settled, full opacity; PLAN.md also allows
        // a fade-in keyed on (1 - alpha), which reads as "labels resolve as the graph does".
        let labelOpacity = simulation.isSettled ? 1.0 : max(0, 1.0 - simulation.alpha)

        for edge in EdgeRenderList.visibleEdges(graph: graph, positions: positions) {
            var path = Path()
            path.move(to: edge.from)
            path.addLine(to: edge.to)
            // Weak edges stay faint but visible, never fully transparent: an invisible edge
            // would read as "no relationship" rather than "a weak one", losing exactly the
            // clustering signal the layout exists to show. Real strength is a distinct-day
            // count that reaches into the hundreds for a long-running thread; a linear
            // opacity ramp saturates at strength ~9 and every real edge would render
            // identically. sqrt (same treatment ForceSimulation gives spring stiffness, for
            // the same reason) keeps the ramp meaningful across that whole range.
            let opacity = min(1.0, 0.08 + 0.12 * (edge.strength + 1).squareRoot())
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 0.75)
        }

        for id in simulation.orderedNodeIDs {
            guard let position = positions[id], let node = nodesByID[id] else { continue }
            let radius = simulation.radius(for: id) ?? 6
            let rect = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(NodeColor.color(for: node.kind)))

            guard labelOpacity > 0, labelNodeIDs.contains(id) else { continue }
            var labelContext = context
            labelContext.opacity = labelOpacity
            let label = node.name ?? id
            let resolvedText = labelContext.resolve(Text(label).font(.system(size: 10)).foregroundColor(.white))
            labelContext.draw(resolvedText, at: CGPoint(x: position.x + radius + 4, y: position.y), anchor: .leading)
        }
    }
}
