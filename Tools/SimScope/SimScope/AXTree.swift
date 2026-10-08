/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import CoreGraphics
import FBAXCore
import FBControlCore
import Foundation
import SimScopeProtocol

/// A single accessibility element flattened out of the frontmost app's tree, carrying its depth so a
/// table can render the hierarchy with indentation. Frames are in simulator screen points.
struct AXNode: Equatable {
  let depth: Int
  let type: String?
  let label: String?
  let identifier: String?
  let value: String?
  let frame: CGRect?

  /// The centre of the element's frame — where a "tap this row" gesture is delivered. `nil` for
  /// elements with no usable frame (which therefore cannot be tapped).
  var tapPoint: CGPoint? {
    guard let frame, frame.width > 0, frame.height > 0 else { return nil }
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  /// A natural-language noun phrase for the action log, matching `AXHit.phrase`.
  var phrase: String {
    var phrase = type?.nonEmpty ?? "element"
    if let label, !label.isEmpty { phrase += " “\(label)”" }
    if let identifier, !identifier.isEmpty { phrase += " (id: \(identifier))" }
    return phrase
  }

  /// Whether this element provides anything worth showing: a label, an identifier, or a value. Bare
  /// structural containers (`Any`, unlabelled images, numeric-only types) provide nothing and are
  /// pruned. Deliberately content-based, not role-based, so meaningful *non-interactable* elements
  /// (labelled static text, value-bearing elements) are kept — unlike the serializer's `.interactable`
  /// filter, which would drop them.
  var isMeaningful: Bool {
    (label?.isEmpty == false) || (identifier?.isEmpty == false) || (value?.isEmpty == false)
  }

  /// What the reader reported about acting on this element, when it was asked for. `nil` means the
  /// `interactable` key was not requested or the backend predates it — the role heuristic stands in.
  var interactability: Interactability?

  /// Whether this element is an interactive control (as opposed to informative-but-static content).
  ///
  /// Prefers what the reader reported over what the role implies. The role heuristic cannot see whether
  /// an element is actually reachable, so it calls a covered button interactive — which is the exact
  /// claim the overlay exists to stop making.
  var isInteractive: Bool { isControl && interactability != .blockedOtherwise }

  /// Whether this element is a tap candidate, as reported by the reader.
  ///
  /// There is deliberately no role-based fallback. Guessing from an element's type is wrong in both
  /// directions — a covered button reads as reachable, a tappable row typed `Any` reads as content —
  /// and a wrong answer here is worse than none, because the overlay exists precisely to stop the
  /// viewer inferring reachability. If nothing is drawn, the reader did not report, and that is a
  /// fact worth seeing rather than papering over.
  var isControl: Bool { interactability != nil && interactability != .nonInteractive }

  /// A control a tap would reach.
  var isReachableControl: Bool { interactability == .actionable }

  /// A control that is present and framed but covered — the case the overlay exists to show.
  var isOccludedControl: Bool {
    if case .occluded = interactability { return true }
    return false
  }

  /// True when the element is covered by something else — the case where the frame is right, the
  /// element is real, and only the midpoint is wrong.
  ///
  /// Deliberately narrower than `blocked`. Most blocked elements are blocked for reasons that have
  /// nothing to do with occlusion — static text and containers report `userInteractionDisabled` or
  /// `notHittable` simply for never having been controls — and colouring those would bury the one case
  /// the overlay exists to show.
  var isOccluded: Bool {
    if case .occluded = interactability { return true }
    return false
  }

  /// How the overlay should colour an element.
  enum Interactability: Equatable {
    /// Reachable — the reader gave a point that works.
    case actionable
    /// Covered by another element: present and framed, but not reachable at its centre. Carries what
    /// is on top, where the reader named it — an occluded point is only actionable knowledge if you
    /// know what to move.
    case occluded(String?)
    /// Its own child or container takes the touch. Carries what to tap instead — the reader resolved
    /// a relative in this same tree, so unlike `occluded` there is always something to point at.
    case handledBy(String)
    /// Not actionable for some reason other than occlusion — never a control, disabled, zero-sized.
    case blockedOtherwise
    /// Informative content rather than a control.
    case nonInteractive
    /// The reader returned a negative verdict this app does not believe — currently a bare
    /// `notHittable`, which fires on ordinary rows whose centre hit-test resolves to a child. Kept as
    /// its own state rather than folded into "no verdict", because "measured and disbelieved" and
    /// "never measured" are different facts, and rendering them identically hides whichever one is
    /// the bug. On the semantic strategy this is currently EVERY element, because the translator walk
    /// omits the point attribute the hittability check needs.
    case reportedUnhittable
  }

  /// The indented one-line rendering shown in the tree table.
  ///
  /// Carries the reported reachability where there is one. Without it the row shows a label and a role
  /// and the viewer has to infer whether a tap would land — which is the inference the overlay exists
  /// to remove, so leaving it out of the tree just moves the guessing somewhere else.
  var displayText: String {
    let indent = String(repeating: "   ", count: depth)
    var parts: [String] = [type?.nonEmpty ?? "element"]
    if let label, !label.isEmpty { parts.append("“\(AXNode.renderedLabel(label))”") }
    if let identifier, !identifier.isEmpty { parts.append("#\(identifier)") }
    if let value, !value.isEmpty { parts.append("= \(value.prefix(120))") }
    // The glyph leads the row, ahead of the indent, so every state lines up in one gutter down the
    // left of the table — a column, without needing the tree to stop being an outline view.
    return stateGlyph + " " + indent + parts.joined(separator: " ")
  }

  /// A label short enough to be a table row, with its true size stated when it is not.
  static func renderedLabel(_ label: String) -> String {
    guard label.count > labelPreviewThreshold else { return label }
    let formatted = NumberFormatter.localizedString(
      from: NSNumber(value: label.count), number: .decimal)
    let firstLine = label.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? label
    return "⚠️ \(formatted)-character label — \(firstLine.prefix(90))…"
  }

  private static let labelPreviewThreshold = 400

  /// One character of reported reachability, in a fixed-width gutter.
  ///
  /// A glyph rather than a word because the reader is scanning a hundred rows for the odd one out, and
  /// a colour difference is found far faster than a bracketed adjective at the end of a long line.
  var stateGlyph: String {
    switch interactability {
    case .actionable: return "🟢"
    case .occluded: return "🟡"
    case .handledBy: return "🔵"
    case .blockedOtherwise: return "🔴"
    case .nonInteractive: return "⚪️"
    case .reportedUnhittable: return "🟣"
    case nil: return "▫️"
    }
  }

  /// Spelled-out reachability for the hover tooltip, where there is room for a sentence.
  var interactabilityBadge: String? {
    switch interactability {
    case .actionable: return "reachable — a tap at the reported point lands here"
    case let .occluded(by):
      return by.map { "covered by \($0) — present and framed, but not reachable at its centre" }
        ?? "covered — present and framed, but something is on top of its centre"
    case let .handledBy(target): return "handled by \(target) — tap that instead"
    case .blockedOtherwise: return "not actionable — disabled, zero-sized, or never a control"
    case .nonInteractive: return "content — informative, not a control"
    case .reportedUnhittable:
      return "the reader called this unhittable and this app does not believe it — the verdict fires on ordinary rows, and on the semantic strategy it fires on everything"
    case nil: return nil
    }
  }
}

extension AccessibilityDocumentElement {
  /// This element's frame as a `CGRect` (simulator points), or nil if it has none.
  var simFrame: CGRect? {
    guard
      let frameField = frame, let frame = frameField,
      let x = frame.x, let y = frame.y, let width = frame.width, let height = frame.height
    else {
      return nil
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

extension AXNode {

  init(element: AccessibilityDocumentElement, depth: Int) {
    self.depth = depth
    self.type = element.type.flatMap { $0 }
    self.label = element.label.flatMap { $0 }
    self.identifier = element.identifier.flatMap { $0 }
    self.value = element.value.flatMap { $0 }.map(AXNode.string(from:))

    // Frame first: the interactability verdict below is cross-checked against it.
    let parsedFrame: CGRect?
    if let frameField = element.frame, let frame = frameField,
      let x = frame.x, let y = frame.y, let width = frame.width, let height = frame.height
    {
      parsedFrame = CGRect(x: x, y: y, width: width, height: height)
    } else {
      parsedFrame = nil
    }
    self.frame = parsedFrame

    switch element.interactable.flatMap({ $0 }) {
    case .actionable:
      self.interactability = .actionable
    case let .blocked(reasons):
      let occluder = reasons.compactMap { reason -> String?? in
        guard case let .occluded(by) = reason else { return nil }
        return by.map {
          $0.label?.nonEmpty ?? $0.identifier?.nonEmpty
            ?? $0.type?.nonEmpty.map { $0 == "Any" ? "an untyped view" : $0 }
        }
      }.first
      let handler = reasons.compactMap { reason -> String? in
        guard case let .handledBy(ref) = reason, let ref else { return nil }
        return ref.label?.nonEmpty ?? ref.identifier?.nonEmpty
          ?? ref.type?.nonEmpty.map { $0 == "Any" ? "an untyped view" : $0 }
      }.first
      let zeroSize = reasons.contains { if case .zeroSize = $0 { return true } else { return false } }
      // A `zeroSize` verdict on an element the tree reports with a real frame is self-contradictory —
      // the reason is derived from a frame the reader did not have. Treat the whole verdict as absent
      // rather than believe it, so the role heuristic stands in instead of the screen going blank.
      // Only `occluded` is trusted, because it is the only reason that tells the overlay something the
      // role cannot. The others fire broadly — `zeroSize` lands on elements the tree reports with real
      // frames, and `notHittable` on ordinary list rows whose centre hit-test resolves to a child — so
      // believing them empties the overlay on screens composed entirely of controls. Treated as no
      // verdict rather than as a negative one, which leaves the role heuristic in charge.
      _ = zeroSize
      // `handledBy` is believed where the bare `notHittable` it replaces was not: it only fires when
      // the hit-test resolved to a relative in this same tree, so it always has a target to name.
      let notHittable = reasons.contains { if case .notHittable = $0 { return true } else { return false } }
      if let occluder {
        self.interactability = .occluded(occluder ?? nil)
      } else if let handler {
        self.interactability = .handledBy(handler)
      } else if notHittable {
        self.interactability = .reportedUnhittable
      } else {
        self.interactability = nil
      }
    case nil:
      self.interactability = nil
    }
  }

  /// Depth-first flattening of a `complete`-format document's nested elements.
  ///
  /// Unless `includeAll`, elements that provide nothing (`isMeaningful == false`) are dropped and their
  /// meaningful descendants hoisted to the dropped node's depth, so the table shows the actionable /
  /// informative elements without the structural `Any` noise while preserving hierarchy.
  static func flatten(_ elements: [AccessibilityDocumentElement], includeAll: Bool = false) -> [AXNode] {
    var rows: [AXNode] = []
    func walk(_ elements: [AccessibilityDocumentElement], depth: Int) {
      for element in elements {
        let node = AXNode(element: element, depth: depth)
        let children = element.children ?? []
        if includeAll || node.isMeaningful {
          rows.append(node)
          walk(children, depth: depth + 1)
        } else {
          walk(children, depth: depth) // hoist kept descendants up in place of this node
        }
      }
    }
    walk(elements, depth: 0)
    return rows
  }

  private static func string(from value: AccessibilityAttributeValue) -> String {
    switch value {
    case let .string(string): return string
    case let .bool(bool): return bool ? "true" : "false"
    case let .int(int): return String(int)
    case let .double(double): return String(double)
    case .array, .object: return "…"
    case .null: return "null"
    }
  }
}

/// The proportion of the simulator screen covered by (meaningful) accessibility elements, split by
/// interactivity. Areas are *unions*, computed by rasterizing element frames onto a coarse grid, so
/// overlapping/nested frames are not double-counted (`total <= 1.0`). `interactive` and
/// `nonInteractive` may overlap each other, so they need not sum to `total`.
struct Coverage: Equatable {
  var total: Double
  var interactive: Double
  var nonInteractive: Double
  var count: Int
  /// How many elements the reader returned no reachability verdict for. Tracked separately because
  /// "not reported" and "reported as not interactive" are different facts, and conflating them turns
  /// a missing measurement into a false claim — a screen of tappable settings rows read through a
  /// strategy that does not fetch `interactable` would otherwise print "non-interactive 100%".
  var unjudged: Int = 0
  /// Elements the reader called unhittable and this app declined to believe. Reported separately for
  /// the same reason as `unjudged`: it is the number that tells you the reader is wrong rather than
  /// silent, and on the semantic strategy it is currently every element on the screen.
  var disbelieved: Int = 0
  /// Elements the reader returned with no usable frame, which therefore cannot be located or tapped.
  ///
  /// These contribute no area, so coverage percentages alone cannot report missing geometry.
  var positionless: Int = 0
  /// Elements whose reported tap point lies outside the screen, and so cannot be tapped.
  var offScreen: Int = 0

  static let empty = Coverage(
    total: 0, interactive: 0, nonInteractive: 0, count: 0, unjudged: 0, disbelieved: 0,
    positionless: 0, offScreen: 0)

  private func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

  /// The one-line status under the tree, e.g. `84 elements  ·  covering 62% of the screen`.
  ///
  /// Deliberately short, and in words rather than in this app's vocabulary. It is read at a glance,
  /// during a demo, by people who did not build it, so it carries only facts a viewer can check against
  /// the screen sitting next to it. The fussier counts — what the reader declined to judge, what it
  /// claimed and was not believed — are still worth having and still tracked, but they live in `detail`
  /// on hover: a bar that states six things nobody can act on does not get read at all.
  var summary: String {
    let elements = "\(count) element\(count == 1 ? "" : "s")"
    guard count > 0 else { return elements }
    if positionless == count {
      return "\(elements)  ·  none positioned, none tappable"
    }
    var parts: [String] = [elements]
    if positionless > 0 {
      // The denominator is named rather than assumed. An unqualified "covering 62%" beside "52 elements
      // unpositioned" contradicts itself — the area was measured over the handful that had a frame, and
      // saying so is what stops it reading as a claim about the whole screen.
      parts.append("\(positionless) element\(positionless == 1 ? "" : "s") unpositioned")
      parts.append("the other \(count - positionless) cover \(pct(total)) of the screen")
    } else {
      parts.append("covering \(pct(total)) of the screen")
    }
    if offScreen > 0 { parts.append("\(offScreen) element\(offScreen == 1 ? "" : "s") offscreen") }
    return parts.joined(separator: "  ·  ")
  }

  /// The full picture, shown on hover over the status line.
  var detail: String {
    var parts = [
      "\(count) elements  ·  interactive \(pct(interactive))  ·  non-interactive \(pct(nonInteractive))"
    ]
    if positionless > 0 { parts.append("\(positionless) came back with no frame, so cannot be located") }
    if offScreen > 0 { parts.append("\(offScreen) report a tap point outside the screen") }
    if unjudged > 0 {
      parts.append("\(unjudged) with no reachability verdict — this read did not ask what is on top")
    }
    if disbelieved > 0 {
      parts.append("\(disbelieved) the reader called unhittable, which this app did not believe")
    }
    return parts.joined(separator: "\n")
  }

  /// Unions each node's frame onto a ~4pt grid (clipped to the screen) and returns the covered fraction
  /// overall and per interactivity class.
  static func compute(nodes: [AXNode], screen: CGSize) -> Coverage {
    guard screen.width > 0, screen.height > 0 else { return .empty }
    let cellSize: CGFloat = 4
    let columns = max(1, Int((screen.width / cellSize).rounded(.up)))
    let rowsCount = max(1, Int((screen.height / cellSize).rounded(.up)))
    let cellCount = columns * rowsCount

    let unjudged = nodes.filter { $0.interactability == nil }.count
    let disbelieved = nodes.filter { $0.interactability == .reportedUnhittable }.count
    let positionless = nodes.filter { $0.tapPoint == nil }.count
    let screenRect = CGRect(origin: .zero, size: screen)
    let offScreen = nodes.filter { node in
      guard let point = node.tapPoint else { return false }
      return !screenRect.contains(point)
    }.count
    var anyGrid = [Bool](repeating: false, count: cellCount)
    var interactiveGrid = [Bool](repeating: false, count: cellCount)
    var nonInteractiveGrid = [Bool](repeating: false, count: cellCount)

    for node in nodes {
      guard let frame = node.frame, frame.width > 0, frame.height > 0 else { continue }
      let x0 = max(0, Int((frame.minX / cellSize).rounded(.down)))
      let y0 = max(0, Int((frame.minY / cellSize).rounded(.down)))
      let x1 = min(columns - 1, Int((frame.maxX / cellSize).rounded(.up)) - 1)
      let y1 = min(rowsCount - 1, Int((frame.maxY / cellSize).rounded(.up)) - 1)
      guard x1 >= x0, y1 >= y0 else { continue }
      let interactive = node.isInteractive
      var gy = y0
      while gy <= y1 {
        let base = gy * columns
        var gx = x0
        while gx <= x1 {
          let index = base + gx
          anyGrid[index] = true
          if interactive { interactiveGrid[index] = true } else { nonInteractiveGrid[index] = true }
          gx += 1
        }
        gy += 1
      }
    }

    func fraction(_ grid: [Bool]) -> Double {
      var covered = 0
      for cell in grid where cell { covered += 1 }
      return Double(covered) / Double(cellCount)
    }

    return Coverage(
      total: fraction(anyGrid),
      interactive: fraction(interactiveGrid),
      nonInteractive: fraction(nonInteractiveGrid),
      count: nodes.count,
      unjudged: unjudged,
      disbelieved: disbelieved,
      positionless: positionless,
      offScreen: offScreen)
  }
}

/// One tree read: the rows to display, the coverage computed over the meaningful elements, and those
/// meaningful nodes themselves (for the coverage visualization overlay).

/// A node in the tree as the outline view sees it: the same `AXNode` payload, plus children and a
/// **stable identity**.
///
/// Identity is what lets the table survive a refresh. Rebuilding the model every second and calling
/// `reloadData` collapses every disclosure triangle and loses the selection, which makes an expandable
/// tree useless on a screen that is being driven. Keyed by identity instead, expansion and selection
/// are restored against the new model and only genuinely changed rows animate.
///
/// The key prefers the app's own accessibility identifier, which is stable by construction and
/// survives the element moving. Where there is none it falls back to type, label and sibling index
/// under the parent's key — stable as long as the screen is, which is the best available for an
/// element the app never named.
/// Built off-main by the reader and consumed on main by the outline view. Immutable once `build`
/// returns, which is what makes handing it across safe.
final class AXOutlineNode: @unchecked Sendable {
  private(set) var node: AXNode
  fileprivate(set) var key: String
  fileprivate(set) var children: [AXOutlineNode] = []
  /// Set during the merge, so revealing a row can walk UP to what it is nested inside instead of
  /// searching down from the roots for it. Weak because the children array owns the other direction.
  fileprivate(set) weak var parent: AXOutlineNode?

  init(node: AXNode, key: String) {
    self.node = node
    self.key = key
  }

  /// Everything the table draws for this row, and nothing else.
  ///
  /// Change is judged against what is rendered rather than against the whole element, so "changed"
  /// means a viewer could see the difference. An attribute that moved but is not on screen is not a
  /// change anyone can check, and counting it would make the refresh look busier than the screen is.
  var rowSignature: String {
    [node.identifierColumn, node.typeColumn, node.contentColumn, node.pointColumn]
      .joined(separator: "\u{1}")
  }

  var subtreeCount: Int { 1 + children.reduce(0) { $0 + $1.subtreeCount } }

  static func build(_ elements: [AccessibilityDocumentElement], includeAll: Bool) -> [AXOutlineNode] {
    func childKey(_ node: AXNode, parent: String, index: Int) -> String {
      if let identifier = node.identifier?.nonEmpty { return parent + "/#" + identifier }
      let type = node.type ?? "?"
      let label = node.label?.prefix(40) ?? ""
      return "\(parent)/\(index).\(type).\(label)"
    }
    func walk(_ elements: [AccessibilityDocumentElement], depth: Int, parent: String) -> [AXOutlineNode] {
      var built: [AXOutlineNode] = []
      for (index, element) in elements.enumerated() {
        let node = AXNode(element: element, depth: depth)
        let kids = element.children ?? []
        if includeAll || node.isMeaningful {
          let key = childKey(node, parent: parent, index: index)
          let outline = AXOutlineNode(node: node, key: key)
          outline.children = walk(kids, depth: depth + 1, parent: key)
          built.append(outline)
        } else {
          // Hoist meaningful descendants in place of a container that says nothing, keyed under the
          // same parent so the hoist does not itself change identity.
          built.append(contentsOf: walk(kids, depth: depth, parent: parent))
        }
      }
      return built
    }
    var roots = walk(elements, depth: 0, parent: "")
    makeSiblingKeysUnique(&roots)
    return roots
  }

  /// Two siblings can legitimately carry the same accessibility identifier, and identity has to be
  /// unique or a refresh cannot tell them apart — it would retire one row and insert another on every
  /// read, forever. Suffixing only the repeats leaves the common case byte-identical.
  private static func makeSiblingKeysUnique(_ nodes: inout [AXOutlineNode]) {
    var seen: [String: Int] = [:]
    for node in nodes {
      let occurrence = (seen[node.key] ?? 0) + 1
      seen[node.key] = occurrence
      if occurrence > 1 { node.key += "~\(occurrence)" }
      makeSiblingKeysUnique(&node.children)
    }
  }
}

/// A screen point rounded to whole points, hashable, for looking a node up by where it is.
///
/// Rounded on purpose: the two sides of a lookup come from different reads — a hit-test and a tree
/// walk — and agree to well under a point but not to the bit.
struct PointKey: Hashable {
  let x: Int
  let y: Int
  init(_ point: CGPoint) {
    x = Int(point.x.rounded())
    y = Int(point.y.rounded())
  }
}

/// The merged tree, what changed in it, and the indexes for finding a node without walking.
struct TreeMerge {
  let roots: [AXOutlineNode]
  let delta: TreeDelta
  /// Every node by identity, so restoring a selection is a lookup rather than a scan of the table.
  let byKey: [String: AXOutlineNode]
  /// Every positioned node by the centre of its frame — the one coordinate both a tap and a hit-test
  /// resolve to. An array per point because two elements can share a centre exactly (a control and the
  /// container drawn around it), and picking between them is the caller's business.
  let byCentre: [PointKey: [AXOutlineNode]]
}

/// What a refresh did to the tree, in terms that can be checked against the screen.
struct TreeDelta {
  var added = 0
  var removed = 0
  var changed = 0
  var unchanged = 0
  var changedKeys: Set<String> = []

  /// Whether every surviving row kept its place — same keys, same order, same nesting.
  ///
  /// This is the licence to animate. When identity holds, the two states are the same rows wearing
  /// different values and a transition between them is something that really happened. When it does
  /// not, the screen moved, and interpolating would draw a motion nobody performed — so that case
  /// snaps instead.
  var structureHeld = true

  var summary: String {
    var parts: [String] = []
    if added > 0 { parts.append("\(added) new") }
    if removed > 0 { parts.append("\(removed) gone") }
    if changed > 0 { parts.append("\(changed) changed") }
    parts.append("\(unchanged) same")
    return parts.joined(separator: " · ")
  }
}

extension AXOutlineNode {
  /// Merge a freshly read tree into the one already on screen, keeping the object for every key that
  /// came back.
  ///
  /// WHY REUSE RATHER THAN REPLACE. `NSOutlineView` tracks rows by object identity. A read that builds
  /// a whole new object graph makes every row a stranger to the table, so the only legal update is
  /// `reloadData` — which throws away expansion, selection and scroll position and blinks the entire
  /// table on every poll. Reusing the object for a surviving key lets a refresh be expressed as the few
  /// rows that actually moved. That is what makes both the delta count and the animation honest: a row
  /// can only animate if it is the same row.
  static func reconcile(_ existing: [AXOutlineNode], with fresh: [AXOutlineNode]) -> TreeMerge {
    var delta = TreeDelta()
    var byKey: [String: AXOutlineNode] = [:]
    var byCentre: [PointKey: [AXOutlineNode]] = [:]
    // Built here rather than in a pass of its own: the merge already visits every node, and a second
    // walk to index what the first one just touched is the cost this exists to remove.
    let merged = merge(existing, fresh, parent: nil, into: &delta, byKey: &byKey, byCentre: &byCentre)
    return TreeMerge(roots: merged, delta: delta, byKey: byKey, byCentre: byCentre)
  }

  /// Index a wholly new subtree, which the merge does not descend into.
  private static func indexSubtree(
    _ node: AXOutlineNode, into byKey: inout [String: AXOutlineNode],
    _ byCentre: inout [PointKey: [AXOutlineNode]]
  ) {
    byKey[node.key] = node
    if let centre = node.node.tapPoint { byCentre[PointKey(centre), default: []].append(node) }
    for child in node.children {
      child.parent = node
      indexSubtree(child, into: &byKey, &byCentre)
    }
  }

  private static func merge(
    _ old: [AXOutlineNode], _ fresh: [AXOutlineNode], parent: AXOutlineNode?,
    into delta: inout TreeDelta, byKey: inout [String: AXOutlineNode],
    byCentre: inout [PointKey: [AXOutlineNode]]
  ) -> [AXOutlineNode] {
    var survivors: [String: AXOutlineNode] = [:]
    for node in old where survivors[node.key] == nil { survivors[node.key] = node }

    var merged: [AXOutlineNode] = []
    merged.reserveCapacity(fresh.count)
    for (index, incoming) in fresh.enumerated() {
      guard let survivor = survivors.removeValue(forKey: incoming.key) else {
        delta.added += incoming.subtreeCount
        delta.structureHeld = false
        incoming.parent = parent
        indexSubtree(incoming, into: &byKey, &byCentre)
        merged.append(incoming)
        continue
      }
      if index >= old.count || old[index] !== survivor { delta.structureHeld = false }
      let before = survivor.rowSignature
      survivor.node = incoming.node
      if survivor.rowSignature == before {
        delta.unchanged += 1
      } else {
        delta.changed += 1
        delta.changedKeys.insert(survivor.key)
      }
      survivor.parent = parent
      byKey[survivor.key] = survivor
      if let centre = survivor.node.tapPoint {
        byCentre[PointKey(centre), default: []].append(survivor)
      }
      survivor.children = merge(
        survivor.children, incoming.children, parent: survivor, into: &delta, byKey: &byKey,
        byCentre: &byCentre)
      merged.append(survivor)
    }
    for gone in survivors.values {
      delta.removed += gone.subtreeCount
      delta.structureHeld = false
    }
    return merged
  }
}

extension AXNode {
  /// Per-column text for the outline table. Deliberately NOT one pre-rendered string: a single
  /// column of `type "label" #id = value` looks like a table and is not one — it cannot be sorted,
  /// resized, aligned or read down. Real columns let the eye scan one attribute at a time.
  /// Reachability in words rather than a glyph. A colour in a gutter is fast to scan but needs a
  /// legend; the word does not, and this table is read by people who did not build it.
  /// Whether this node is the element a hit-test just returned.
  ///
  /// Identifier and frame together, because neither alone is an identity: an identifier repeats down a
  /// list of cells, and a frame changes the moment the screen scrolls. Unidentified elements — most of a
  /// UIKit tree — fall back to frame plus role plus label, which is the most that can be said about them.
  func matches(_ hit: AXHit) -> Bool {
    guard let frame, frame == hit.frame else { return false }
    if let identifier = identifier?.nonEmpty, let hitIdentifier = hit.identifier?.nonEmpty {
      return identifier == hitIdentifier
    }
    return type == hit.type && label == hit.label
  }

  var stateWord: String {
    switch interactability {
    case .actionable: return "reachable"
    case .occluded: return "covered"
    case let .handledBy(target): return "→ \(target)"
    case .blockedOtherwise: return "blocked"
    case .nonInteractive: return "content"
    case .reportedUnhittable: return "reported unhittable"
    case nil: return ""
    }
  }
  /// `Any` is the serializer's fallback for an element XCTest could not map to an XCUIElementType —
  /// in practice a bare UIView wrapper. It is by far the commonest type on a real screen, and reading
  /// as a placeholder rather than a fact invites the viewer to think something failed. Name it.
  var typeColumn: String {
    guard let type = type?.nonEmpty else { return "—" }
    return type == "Any" ? "untyped view" : type
  }
  /// Label and value in one column. They were two, and the value column was empty on most rows while
  /// carrying the more informative half on the rest — a switch's "Not ticked", a tab's "Unread", a
  /// scroll position. Two columns to say one thing wasted the width that the content itself needed.
  /// Where both exist the label names the thing and the value says what state it is in, so both are
  /// kept and the value is set apart rather than dropped.
  var contentColumn: String {
    let label = label.flatMap { $0.nonEmpty }.map(AXNode.renderedLabel)
    let value = value?.nonEmpty.map { String($0.prefix(90)) }
    switch (label, value) {
    case let (.some(label), .some(value)): return "\(label)  =  \(value)"
    case let (.some(label), .none): return label
    case let (.none, .some(value)): return "=  \(value)"
    case (.none, .none): return ""
    }
  }
  var identifierColumn: String { identifier?.nonEmpty ?? "" }
  /// The colour a reported tap point deserves. The point is the one value a caller acts on, so it is
  /// the right place to carry the warning: a coordinate that will not land should not look identical
  /// to one that will. Green is deliberately absent — reachable is the unremarkable case and does not
  /// need decorating; only the ways it can be wrong are worth a colour.
  /// A wash for the whole row. Tinting one cell puts the signal where the eye is not — you scan a
  /// table by row, so an unreachable element should read as unreachable before you have located the
  /// coordinate column. Kept faint: this sits under alternating row colours and must not fight the
  /// selection highlight.
  var rowTint: NSColor? {
    switch interactability {
    case .occluded: return NSColor.systemYellow.withAlphaComponent(0.16)
    case .handledBy: return NSColor.systemBlue.withAlphaComponent(0.13)
    case .blockedOtherwise: return NSColor.systemRed.withAlphaComponent(0.13)
    case .reportedUnhittable: return NSColor.systemPurple.withAlphaComponent(0.12)
    case .actionable, .nonInteractive, nil: return nil
    }
  }

  var pointTint: NSColor {
    // Checked ahead of the verdict: an element with no position cannot be acted on whatever the
    // reader said about it, so that fact outranks a reachability claim made about the same row.
    if tapPoint == nil { return .systemRed }
    switch interactability {
    case .occluded: return .systemYellow
    case .handledBy: return .systemBlue
    case .blockedOtherwise: return .systemRed
    case .reportedUnhittable: return .systemPurple
    case .actionable, .nonInteractive, nil: return .secondaryLabelColor
    }
  }

  /// The reported point, plus whatever stands between a caller and it. State used to be its own
  /// column; folding it in here puts the warning on the value it qualifies, so a coordinate is never
  /// read without the reason it will not work.
  var pointColumn: String {
    // Named rather than left blank. An empty cell reads as "not measured yet"; this is a reader that
    // returned the element and no way to reach it, which is a finding and should look like one.
    guard let point = tapPoint else { return "no position" }
    let coordinate = "\(Int(point.x.rounded())), \(Int(point.y.rounded()))"
    // The name of whatever is in the way comes from another element's label, and those run long — a
    // settings row's label is a sentence. Clipped here rather than by the column, so the cell truncates
    // at a word the reader chose instead of wherever the column happens to end.
    func named(_ text: String) -> String {
      text.count <= 30 ? text : text.prefix(29).trimmingCharacters(in: .whitespaces) + "…"
    }
    switch interactability {
    case let .occluded(by):
      return by.map { "\(coordinate)  under \(named($0))" } ?? "\(coordinate)  covered"
    case let .handledBy(target): return "\(coordinate)  → \(named(target))"
    case .blockedOtherwise: return "\(coordinate)  blocked"
    case .reportedUnhittable: return "\(coordinate)  reported unhittable — not trusted"
    case .actionable, .nonInteractive, nil: return coordinate
    }
  }
}

struct TreeSnapshot {
  let rows: [AXNode]
  let coverage: Coverage
  let coverageNodes: [AXNode]
  /// The same content as `rows`, nested and identity-keyed, for the outline view.
  let tree: [AXOutlineNode]
  /// Where the read's time went, when the backend reported it.
  ///
  /// Shown because the correctness we now get is bought with latency — asserting accessibility
  /// automation mode exposes subtrees UIKit used to collapse, and a bigger tree costs more to walk. A
  /// single "dump 5480 ms" invites the reader to guess which part is slow; naming the phases, and the
  /// per-node round trips underneath them, answers it instead.
  let cost: String?
}
