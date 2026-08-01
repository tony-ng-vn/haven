import SwiftUI
import GraphCore

/// Renders a settled-or-settling ForceSimulation. Deliberately thin: node/edge selection and
/// styling decisions that are pure computation (which edges draw, which nodes label, focus
/// highlighting, hit testing) live in GraphCore, not here -- this view's own job is driving
/// `tick()`, drawing, and translating raw input events into calls on those pure helpers.
struct GraphView: View {
    let model: AppModel
    let graph: Graph
    let simulation: ForceSimulation

    private let labelNodeIDs: Set<String>
    // graph never changes across GraphView's lifetime (a rebuild tears the whole view down and
    // reconstructs it with a new `graph`), so these lookups are built once here rather than
    // rebuilt every frame inside draw(). Without this, the focus-highlight edge loop below was
    // an O(highlighted edges x total edges) linear scan per frame -- at real-data scale with the
    // user focused (~300+ highlighted involvesUser edges against ~850 total edges), that is
    // hundreds of thousands of string comparisons every single animation tick.
    // Only `kind` and `name` are ever read off these -- both stable for a node's whole life.
    // `degree` is NOT: it reflects the full pre-hide graph, not what excludingNodes recomputes
    // per frame. That is the correct semantics (hiding removes a node from what draws; it does
    // not restate the rest of the graph's numbers), same as simulation.radius(for:) already
    // being pre-hide by design -- but it means nothing here should ever start reading degree.
    private let edgesByID: [String: GraphEdge]
    private let nodesByID: [String: GraphNode]

    @State private var scale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var lastHoverLocation: CGPoint?
    @FocusState private var keyInputFocused: Bool

    init(model: AppModel, graph: Graph, simulation: ForceSimulation) {
        self.model = model
        self.graph = graph
        self.simulation = simulation
        self.labelNodeIDs = LabelBudget.selectedNodeIDs(nodes: graph.nodes)
        self.edgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
        self.nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    }

    var body: some View {
        GeometryReader { proxy in
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
            .background(Color(NodePalette.background))
            .gesture(tapGesture(canvasSize: proxy.size))
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    lastHoverLocation = location
                case .ended:
                    lastHoverLocation = nil
                }
            }
            .contextMenu {
                contextMenuContent(canvasSize: proxy.size)
            }
            .focusable()
            .focused($keyInputFocused)
            .onAppear { keyInputFocused = true }
            .onKeyPress(.escape) {
                model.clearFocus()
                return .handled
            }
        }
    }

    // MARK: - Gestures

    private func tapGesture(canvasSize: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if let hitID = hitTestNode(at: value.location, canvasSize: canvasSize) {
                    model.setFocus(hitID)
                } else {
                    model.clearFocus()
                }
            }
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

    @ViewBuilder
    private func contextMenuContent(canvasSize: CGSize) -> some View {
        let hitID = lastHoverLocation.flatMap { hitTestNode(at: $0, canvasSize: canvasSize) }
        if let hitID {
            Button("Hide \(displayLabel(for: hitID))") {
                model.hideNode(hitID)
            }
            // Remove is structural (drops the person before GraphBuilder, not just from what
            // draws), so it only makes sense for a person: there is no "removed" concept for
            // the user node or a group (a group's equivalent is Hide, already offered above).
            if nodesByID[hitID]?.kind == .person {
                Button("Remove \(displayLabel(for: hitID))") {
                    model.removePerson(hitID)
                }
            }
            // Only a group can be marked -- the acquaintance layer's marker promotes every
            // pair among a GROUP's resolved members (PLAN.md), which is meaningless for a
            // person or the user node. A Toggle (not a Button) so macOS draws the checkmark
            // that shows whether this group is currently marked.
            if nodesByID[hitID]?.kind == .group {
                Toggle(
                    "Everyone here knows each other",
                    isOn: Binding(
                        get: { model.isFullyAcquainted(groupNodeID: hitID) },
                        set: { model.setFullyAcquainted(groupNodeID: hitID, isFullyAcquainted: $0) }
                    )
                )
            }
        } else {
            Button("Hide") {}
                .disabled(true)
        }
    }

    // MARK: - Hit testing

    /// Shared by the click gesture and the context menu: hidden nodes are excluded from both
    /// (still present in `simulation.positions` since hiding is render-only, but nothing the
    /// user can see should be clickable).
    private func hitTestNode(at screenPoint: CGPoint, canvasSize: CGSize) -> String? {
        let hidden = model.displayOptions.hiddenNodeIDs
        let positions = simulation.positions.filter { !hidden.contains($0.key) }
        let radii = simulation.radii.filter { !hidden.contains($0.key) }
        return HitTest.nodeID(
            atScreenPoint: screenPoint,
            canvasSize: canvasSize,
            scale: scale,
            offset: offset,
            positions: positions,
            radii: radii
        )
    }

    private func displayLabel(for id: String) -> String {
        guard let node = nodesByID[id] else { return id }
        return NodeLabel.resolve(node: node, guesses: model.overrides.nameGuesses) ?? id
    }

    // MARK: - Drawing

    private func draw(into context: GraphicsContext, canvasSize: CGSize) {
        var context = context
        // The one transform GraphView applies, and the only one: HitTest inverts this exact
        // same function to convert a click back into canvas space, so drawing and hit
        // testing can never drift apart from each other.
        context.concatenate(HitTest.canvasToScreenTransform(canvasSize: canvasSize, scale: scale, offset: offset))

        let visibleGraph = graph.excludingNodes(model.displayOptions.hiddenNodeIDs)
        let positions = simulation.positions
        let focus = model.focusedNodeID.map { FocusSet.compute(graph: visibleGraph, focusedNodeID: $0) }
        // An unknown or now-hidden focus id resolves to an empty FocusSet; treat that as "no
        // focus" rather than dimming the entire graph to nothing highlighted.
        let hasActiveFocus = (focus?.highlightedNodeIDs.isEmpty == false)

        // While settling: no labels at all. Once settled, full opacity; PLAN.md also allows
        // a fade-in keyed on (1 - alpha), which reads as "labels resolve as the graph does".
        let labelOpacity = simulation.isSettled ? 1.0 : max(0, 1.0 - simulation.alpha)

        drawEdges(into: &context, visibleGraph: visibleGraph, positions: positions, focus: hasActiveFocus ? focus : nil)
        drawNodes(
            into: &context,
            visibleGraph: visibleGraph,
            positions: positions,
            focus: hasActiveFocus ? focus : nil,
            labelOpacity: labelOpacity
        )
    }

    private func drawEdges(
        into context: inout GraphicsContext,
        visibleGraph: Graph,
        positions: [String: CGPoint],
        focus: FocusSet?
    ) {
        // Rest-state edges: everything EdgeRenderList already excludes (user edges, edges to
        // hidden/dead-and-unincluded nodes) stays excluded here too.
        for edge in EdgeRenderList.visibleEdges(graph: visibleGraph, positions: positions) {
            let isHighlighted = focus?.highlightedEdgeIDs.contains(edge.id) ?? true
            let baseOpacity = EdgeRenderList.opacity(forStrength: edge.strength)
            let opacity = focus == nil ? baseOpacity : (isHighlighted ? baseOpacity : 0.03)
            var path = Path()
            path.move(to: edge.from)
            path.addLine(to: edge.to)
            context.stroke(path, with: .color(Color(NodePalette.edge).opacity(opacity)), lineWidth: 0.75)
        }

        // Focus can highlight involvesUser edges (a person's own line to the user, or every
        // such edge when the user itself is focused) that EdgeRenderList never draws at rest.
        // FocusSet's edge list is the single source of truth for what to draw highlighted, so
        // the user-focus case lights the ego edges with zero special-casing here.
        guard let focus else { return }
        for edgeID in focus.highlightedEdgeIDs {
            // Lookup, not a scan: edgesByID is hoisted once in init (see its declaration).
            guard let edge = edgesByID[edgeID], edge.involvesUser else { continue }
            guard let from = positions[edge.nodeIDA], let to = positions[edge.nodeIDB] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(Color(NodePalette.edge).opacity(0.8)), lineWidth: 1.0)
        }
    }

    private func drawNodes(
        into context: inout GraphicsContext,
        visibleGraph: Graph,
        positions: [String: CGPoint],
        focus: FocusSet?,
        labelOpacity: Double
    ) {
        // Just the id set, not a rebuild of the metadata dictionary: nodesByID is hoisted once
        // in init since node kind/name never change across GraphView's lifetime, only which
        // ids are currently visible does.
        let visibleNodeIDs = Set(visibleGraph.nodes.map(\.id))

        for id in simulation.orderedNodeIDs {
            guard visibleNodeIDs.contains(id), let position = positions[id], let node = nodesByID[id] else { continue }
            let radius = simulation.radius(for: id) ?? 6
            let isHighlighted = focus?.highlightedNodeIDs.contains(id) ?? true
            let nodeOpacity = focus == nil ? 1.0 : (isHighlighted ? 1.0 : 0.15)

            let rect = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(NodeColor.color(for: node.kind).opacity(nodeOpacity)))

            if id == model.focusedNodeID {
                let ringRect = rect.insetBy(dx: -3, dy: -3)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }

            // The focused node always shows its label, regardless of the top-40 budget.
            let showsLabel = labelNodeIDs.contains(id) || id == model.focusedNodeID
            guard labelOpacity > 0, showsLabel else { continue }
            var labelContext = context
            labelContext.opacity = labelOpacity * nodeOpacity
            // NodeLabel is the single shared rule with export (GraphImageRenderer): a real
            // name wins, a cached guess shows tilde-prefixed. The screen keeps its own
            // fallback to the raw id when neither exists -- export's fallback (no label at
            // all) is a deliberate difference, not something NodeLabel decides for either.
            let label = NodeLabel.resolve(node: node, guesses: model.overrides.nameGuesses) ?? id
            let resolvedText = labelContext.resolve(Text(label).font(.system(size: 10)).foregroundColor(Color(NodePalette.label)))
            labelContext.draw(resolvedText, at: CGPoint(x: position.x + radius + 4, y: position.y), anchor: .leading)
        }
    }
}
