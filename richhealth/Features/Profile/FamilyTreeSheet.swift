import SwiftUI

//  Family graph sheet — the iOS half of the feature; Android's twin lives in
//  Utils/FamilyGraph.java + Utils/FamilyTreeView.java.
//
//  IMPORTANT — what this is and is not. The backend stores family as a FLAT list:
//  every relative is described only in relation to the signed-in user ("Father",
//  "Maternal Aunt", …). There is no relative-to-relative edge data, so nothing
//  records that a user's father and mother are a couple, or which side a
//  grandparent belongs to. What we can draw is therefore a hub graph laid out BY
//  GENERATION, inferred from the relationship label alone — not a genealogical
//  tree. Row position is the only claim it makes.

// MARK: - Rows

/// Generation offset from the signed-in user. `.other` is not a generation — it
/// collects people whose label carries no placement we can trust.
enum FamilyTreeRow: Int, CaseIterable, Comparable {
    case grandparents  = -2
    case parents       = -1
    case you           =  0
    case children      =  1
    case grandchildren =  2
    case other         = 99

    var title: String {
        switch self {
        case .grandparents:  return "Grandparents"
        case .parents:       return "Parents"
        case .you:           return "You"
        case .children:      return "Children"
        case .grandchildren: return "Grandchildren"
        case .other:         return "Other family"
        }
    }

    static func < (lhs: FamilyTreeRow, rhs: FamilyTreeRow) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Node

struct FamilyNode: Identifiable, Equatable {
    let id: String
    let name: String
    let relationship: String
    let row: FamilyTreeRow
    /// Lower sorts closer to the centre of its row.
    let order: Int
    var isSelf = false
    var isPro = false
    var isPending = false
    var isDeceased = false

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? "?" : s
    }

    /// What the card shows under the name.
    var caption: String {
        if isPending { return "Invite pending" }
        return relationship.isEmpty ? "Family" : relationship
    }
}

// MARK: - Relationship → row

/// Keys are lower-cased. Covers every option in both apps' pickers plus the
/// gender-neutral labels the backend emits when a relative's gender is unset.
/// Kept in step with FamilyGraph.java on Android.
private let familyRowMap: [String: (row: FamilyTreeRow, order: Int)] = [
    "grandfather":     (.grandparents, 0),
    "grandmother":     (.grandparents, 0),
    "grandparent":     (.grandparents, 1),

    "father":          (.parents, 0),
    "mother":          (.parents, 0),
    "parent":          (.parents, 1),
    "paternal uncle":  (.parents, 2),
    "paternal aunt":   (.parents, 2),
    "maternal uncle":  (.parents, 2),
    "maternal aunt":   (.parents, 2),
    "uncle":           (.parents, 3),
    "aunt":            (.parents, 3),
    "aunt/uncle":      (.parents, 3),

    "spouse":          (.you, 0),
    "husband":         (.you, 0),
    "wife":            (.you, 0),
    "brother":         (.you, 1),
    "sister":          (.you, 1),
    "sibling":         (.you, 1),
    "cousin":          (.you, 2),

    "son":             (.children, 0),
    "daughter":        (.children, 0),
    "child":           (.children, 1),
    "nephew":          (.children, 2),
    "niece":           (.children, 2),
    "nephew/niece":    (.children, 2),

    "grandson":        (.grandchildren, 0),
    "granddaughter":   (.grandchildren, 0),
    "grandchild":      (.grandchildren, 1),
]

private func placement(for relationship: String?) -> (row: FamilyTreeRow, order: Int) {
    guard let key = relationship?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          let hit = familyRowMap[key] else {
        return (.other, 100)
    }
    return hit
}

// MARK: - Payload for /api/dependents
// DependentsResponse in HealthDataModels covers /api/dependents/users, which
// carries `dependentType`. The embedded-profile endpoint uses `type` instead
// (child | deceased), so it needs its own shape.

private struct EmbeddedDependentRecord: Decodable {
    let id: String
    let name: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type
    }
}

private struct EmbeddedDependentsResponse: Decodable {
    let dependents: [EmbeddedDependentRecord]
}

// MARK: - ViewModel

@Observable @MainActor
final class FamilyTreeViewModel {
    var isLoading = false
    var nodes: [FamilyNode] = []
    var loadFailed = false

    private let client = APIClient()

    var memberCount: Int { nodes.filter { !$0.isSelf }.count }

    /// Pulls all three family sources together. Each is tolerated independently —
    /// one failing endpoint degrades the graph rather than emptying it.
    func load(selfName: String?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Same shape as ChatService.getDependents: fire together, tolerate each
        // failure separately so a partial result still draws.
        async let relResp = client.send(
            Endpoint(path: "/api/users/relationships", showsLoader: false),
            as: RelationshipsResponse.self)
        async let depUsersResp = client.send(
            Endpoint(path: "/api/dependents/users", showsLoader: false),
            as: DependentsResponse.self)
        async let embeddedResp = client.send(
            Endpoint(path: "/api/dependents", showsLoader: false),
            as: EmbeddedDependentsResponse.self)

        let rel = try? await relResp
        let depUsers = try? await depUsersResp
        let embedded = try? await embeddedResp
        loadFailed = rel == nil && depUsers == nil && embedded == nil

        nodes = Self.build(selfName: selfName,
                           relationships: rel?.relationships ?? [],
                           dependentUsers: depUsers?.dependents ?? [],
                           embedded: embedded?.dependents ?? [])
    }

    /// Merge the three sources into one ordered node list, de-duplicating anyone
    /// held in more than one of them.
    static func build(selfName: String?,
                      relationships: [RelationshipRecord],
                      dependentUsers: [DependentRecord],
                      embedded: [EmbeddedDependentRecord]) -> [FamilyNode] {

        let name = (selfName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "You"
        var out: [FamilyNode] = [
            FamilyNode(id: "__self__", name: name, relationship: "You",
                       row: .you, order: -1, isSelf: true)
        ]

        var seen = Set<String>()

        func claim(_ key: String?) -> Bool {
            guard let key, !key.isEmpty else { return false }
            return seen.insert(key.lowercased()).inserted
        }

        for r in relationships {
            let key = r.userId.flatMap { $0.isEmpty ? nil : "id:\($0)" }
                ?? r.email.flatMap { $0.isEmpty ? nil : "em:\($0)" }
                ?? r.name.flatMap { $0.isEmpty ? nil : "nm:\($0)" }
            guard claim(key) else { continue }

            let place = placement(for: r.relationship)
            let display = [r.name, r.email]
                .compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "Unknown"
            out.append(FamilyNode(
                id: key ?? UUID().uuidString,
                name: display,
                relationship: r.relationship ?? "",
                row: place.row,
                order: place.order,
                isPro: r.isPro ?? false,
                // getFamilyRelationships marks accepted relatives "accepted";
                // anything else in that array is an invite still in flight.
                isPending: r.status.lowercased() != "accepted"
            ))
        }

        for d in dependentUsers {
            guard claim("id:\(d.id)") else { continue }
            // dependentType is the only relationship signal these records carry.
            let (row, label, order): (FamilyTreeRow, String, Int)
            switch d.dependentType?.lowercased() {
            case "child": (row, label, order) = (.children, "Child", 1)
            case "elder": (row, label, order) = (.parents, "Elder", 1)
            default:      (row, label, order) = (.other, "Dependent", 100)
            }
            out.append(FamilyNode(id: "id:\(d.id)", name: d.name ?? "Unknown",
                                  relationship: label, row: row, order: order))
        }

        for e in embedded {
            guard claim("id:\(e.id)") else { continue }
            if e.type?.lowercased() == "child" {
                out.append(FamilyNode(id: "id:\(e.id)", name: e.name ?? "Unknown",
                                      relationship: "Child", row: .children, order: 1))
            } else {
                // "deceased" profiles exist to carry hereditary history and hold no
                // relationship field, so there is nothing to place them on. Listed
                // under Other family rather than guessed onto an ancestor row.
                out.append(FamilyNode(id: "id:\(e.id)", name: e.name ?? "Unknown",
                                      relationship: "In memory", row: .other, order: 100,
                                      isDeceased: true))
            }
        }

        // Closest relations nearest the centre of their row, pending invites last.
        return out.sorted { a, b in
            if a.isPending != b.isPending { return !a.isPending }
            if a.order != b.order { return a.order < b.order }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Layout

private enum TreeMetrics {
    static let cardW: CGFloat = 100
    static let cardH: CGFloat = 104
    static let gapX: CGFloat  = 12
    static let rowGap: CGFloat = 60
    static let labelH: CGFloat = 24
    static let avatar: CGFloat = 42
    static let corner: CGFloat = 16
    static let edgePad: CGFloat = 16
}

private struct TreeLayout {
    struct Placed: Identifiable { let id: String; let node: FamilyNode; let rect: CGRect }
    struct Band {
        let row: FamilyTreeRow
        let labelY: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        let centersX: [CGFloat]
    }
    var placed: [Placed] = []
    var bands: [Band] = []
    var size: CGSize = .zero
}

/// Places every node into content-space rectangles. Rows are centred on a shared
/// axis, so the signed-in user sits on the vertical centre line.
private func computeLayout(_ nodes: [FamilyNode]) -> TreeLayout {
    var layout = TreeLayout()
    guard !nodes.isEmpty else { return layout }

    var buckets: [FamilyTreeRow: [FamilyNode]] = [:]
    for n in nodes { buckets[n.row, default: []].append(n) }

    // The build step sorts the user first in their row (order -1); move them to the
    // middle so they actually sit on the centre line the connectors converge on.
    for (row, var bucket) in buckets {
        guard let selfIdx = bucket.firstIndex(where: { $0.isSelf }) else { continue }
        let mid = bucket.count / 2
        let node = bucket.remove(at: selfIdx)
        bucket.insert(node, at: min(mid, bucket.count))
        buckets[row] = bucket
    }

    let m = TreeMetrics.self
    let widest = FamilyTreeRow.allCases.reduce(CGFloat.zero) { acc, row in
        guard let c = buckets[row]?.count, c > 0 else { return acc }
        return max(acc, CGFloat(c) * m.cardW + CGFloat(c - 1) * m.gapX)
    }

    var y: CGFloat = 0
    for row in FamilyTreeRow.allCases {
        guard let bucket = buckets[row], !bucket.isEmpty else { continue }

        let rowW = CGFloat(bucket.count) * m.cardW + CGFloat(bucket.count - 1) * m.gapX
        var x = (widest - rowW) / 2
        let top = y + m.labelH
        var centers: [CGFloat] = []

        for node in bucket {
            let rect = CGRect(x: x, y: top, width: m.cardW, height: m.cardH)
            layout.placed.append(.init(id: node.id, node: node, rect: rect))
            centers.append(rect.midX)
            x += m.cardW + m.gapX
        }

        layout.bands.append(.init(row: row, labelY: y + m.labelH / 2,
                                  top: top, bottom: top + m.cardH, centersX: centers))
        y = top + m.cardH + m.rowGap
    }

    layout.size = CGSize(width: widest, height: layout.bands.last?.bottom ?? 0)
    return layout
}

/// Org-chart connectors: a horizontal bus between adjacent generation rows with a
/// short stub from every card. The `.other` strip is deliberately NOT connected —
/// those people have no known generation and a line would assert one.
private func connectorPath(_ layout: TreeLayout) -> Path {
    var path = Path()
    guard layout.bands.count > 1 else { return path }

    for i in 0..<(layout.bands.count - 1) {
        let upper = layout.bands[i]
        let lower = layout.bands[i + 1]
        if upper.row == .other || lower.row == .other { continue }

        let busY = (upper.bottom + lower.top) / 2
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude

        for cx in upper.centersX {
            path.move(to: CGPoint(x: cx, y: upper.bottom))
            path.addLine(to: CGPoint(x: cx, y: busY))
            minX = min(minX, cx); maxX = max(maxX, cx)
        }
        for cx in lower.centersX {
            path.move(to: CGPoint(x: cx, y: busY))
            path.addLine(to: CGPoint(x: cx, y: lower.top))
            minX = min(minX, cx); maxX = max(maxX, cx)
        }
        if maxX > minX {
            path.move(to: CGPoint(x: minX, y: busY))
            path.addLine(to: CGPoint(x: maxX, y: busY))
        }
    }
    return path
}

// MARK: - Sheet

struct FamilyTreeSheet: View {
    let selfName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var vm = FamilyTreeViewModel()

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var didFit = false
    @State private var selected: FamilyNode?
    /// Computed once per data change, never per gesture frame.
    @State private var layout = TreeLayout()

    private var subtitle: String {
        if vm.isLoading { return "Loading your family…" }
        if vm.loadFailed { return "Couldn't load your family" }
        let n = vm.memberCount
        if n == 0 { return "No family connected yet" }
        return n == 1 ? "1 family member" : "\(n) family members"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.m)

                canvas

                // Honest about what the layout does and does not claim.
                Text("Grouped by generation, based on how each person is related to you. Pinch to zoom, drag to move, double-tap to fit.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s)
            }
            .navigationTitle("Your Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await vm.load(selfName: selfName) }
    }

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                if vm.isLoading {
                    ProgressView().tint(Theme.brandTeal)
                } else if vm.memberCount == 0 {
                    emptyState
                } else {
                    graph(layout)
                        .frame(width: max(layout.size.width, 1),
                               height: max(layout.size.height, 1))
                        .scaleEffect(scale)
                        .offset(pan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(panGesture.simultaneously(with: zoomGesture))
                        .onTapGesture(count: 2) { fit(in: geo.size, content: layout.size) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Layout is rebuilt only when the data changes; gestures are pure
            // transforms on the already-placed content.
            .onChange(of: vm.nodes) { _, nodes in
                layout = computeLayout(nodes)
                didFit = false
                fit(in: geo.size, content: layout.size)
            }
            .onAppear {
                if layout.placed.isEmpty { layout = computeLayout(vm.nodes) }
                if !didFit { fit(in: geo.size, content: layout.size) }
            }
        }
        .overlay(alignment: .bottom) { selectionPill }
    }

    private func graph(_ layout: TreeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            connectorPath(layout)
                .stroke(Theme.brandTeal.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            ForEach(layout.bands, id: \.row) { band in
                Text(band.row.title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                    .position(x: layout.size.width / 2, y: band.labelY)
            }

            ForEach(layout.placed) { p in
                nodeCard(p.node)
                    .frame(width: p.rect.width, height: p.rect.height)
                    .position(x: p.rect.midX, y: p.rect.midY)
                    .onTapGesture { selected = p.node.isSelf ? nil : p.node }
            }
        }
    }

    private func nodeCard(_ node: FamilyNode) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(node.isSelf
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.brandTeal, Theme.brandTeal.opacity(0.65)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Theme.brandTeal.opacity(node.isPending ? 0.10 : 0.18)))
                    .frame(width: TreeMetrics.avatar, height: TreeMetrics.avatar)

                Text(node.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(node.isSelf ? Color.white : Theme.brandTeal)
                    .opacity(node.isPending ? 0.6 : 1)
            }
            .overlay(alignment: .topTrailing) {
                // Small marker: teal for a Pro member, muted for a memorial entry.
                if node.isPro || node.isDeceased {
                    Circle()
                        .fill(node.isDeceased ? Color.secondary : Theme.brandTeal)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
            }

            Text(node.name)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(node.isPending ? 0.7 : 1)

            Text(node.caption)
                .font(.system(size: 10.5))
                .foregroundStyle(node.isPending ? Color.orange : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TreeMetrics.corner)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TreeMetrics.corner)
                .stroke(node.isSelf ? Theme.brandTeal.opacity(0.9) : Color.white.opacity(0.10),
                        lineWidth: node.isSelf ? 1.6 : 1)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "person.2")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(vm.loadFailed
                 ? "Couldn't load your family right now."
                 : "No family connected yet.\nAdd relatives from Health to see them here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    @ViewBuilder
    private var selectionPill: some View {
        if let node = selected {
            HStack(spacing: 6) {
                Text(node.name).font(.caption.weight(.semibold))
                Text("·").foregroundStyle(.tertiary)
                Text(node.caption).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.bottom, Theme.Spacing.s)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onTapGesture { selected = nil }
        }
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                pan = CGSize(width: basePan.width + value.translation.width,
                             height: basePan.height + value.translation.height)
            }
            .onEnded { _ in basePan = pan }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(baseScale * value.magnification, 0.45), 2.4)
            }
            .onEnded { _ in baseScale = scale }
    }

    /// Scale and centre so the whole graph is visible.
    private func fit(in viewport: CGSize, content: CGSize) {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0 else { return }

        let sx = (viewport.width - TreeMetrics.edgePad * 2) / content.width
        let sy = (viewport.height - TreeMetrics.edgePad * 2) / content.height
        // Never zoom past 1:1 just to fill the space.
        let next = min(max(min(sx, sy), 0.45), 1)

        withAnimation(.easeOut(duration: 0.25)) {
            scale = next
            pan = .zero
        }
        baseScale = next
        basePan = .zero
        didFit = true
    }
}
