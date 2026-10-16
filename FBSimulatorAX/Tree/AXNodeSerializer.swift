/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import FBSimulatorControl
import Foundation

/// Serializes an `AXElementSnapshot` tree into the typed accessibility schema. Values are kept
/// compatible with the SimulatorBridge output downstream consumers parse.
///
/// Serialization reads nothing: every value comes from a snapshot read against the plan for the same
/// keys (`AXReadPlan(keys:depth:)`).
enum AXNodeSerializer {

  // MARK: - Entry points

  static func recursiveDescription(
    fromSnapshot snapshot: AXElementSnapshot,
    serialization: AXSerialization,
    collector: AccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [AccessibilityDocumentElement] {
    if serialization.nested {
      return nestedRecursiveDescription(fromSnapshot: snapshot, keys: serialization.keys, collector: collector, seenPids: seenPids)
    }
    return flatRecursiveDescription(fromSnapshot: snapshot, keys: serialization.keys, collector: collector, seenPids: seenPids)
  }

  /// The one element a caller named. Its descendants are serialized only in the nested format, so a
  /// flat read plans `.limited(0)`.
  static func formattedDescription(
    ofSnapshot snapshot: AXElementSnapshot,
    serialization: AXSerialization,
    collector: AccessibilityProfilingCollector?
  ) -> AccessibilityDocumentElement {
    let keys = serialization.keys
    var node = decoratedElement(forSnapshot: snapshot, keys: keys, collector: collector, seenPids: nil, isRemote: false)
    guard serialization.nested else {
      return node
    }
    // The target's descendants are built as a subtree of their own, rather than by walking the target
    // itself, so the target is always reported and always carries a `children` array — a filtered walk
    // rooted at the target could drop or replace it. The caller filters these children afterwards.
    var children: [AccessibilityDocumentElement] = []
    for child in snapshot.children {
      children.append(
        contentsOf: nestedRecursiveDescription(fromSnapshot: child, keys: keys, collector: collector, seenPids: nil)
      )
    }
    node.children = children
    return node
  }

  // MARK: - Node

  /// Builds the node for a single element over `keys`.
  ///
  /// An attribute is reported only when requested, and the result records that: a requested attribute
  /// is `.some(value-or-nil)` and an unrequested one stays `nil`, which is what lets the encodings emit
  /// an explicit null for the former and nothing at all for the latter.
  ///
  /// The collector tallies one fetch per requested key, as the plan for `keys` fetched it. Seen-pid dedup
  /// and the `is_remote` tag live in `decoratedElement`.
  static func nodeElement(
    forSnapshot snapshot: AXElementSnapshot,
    keys: Set<AXKeys>,
    collector: AccessibilityProfilingCollector?
  ) -> AccessibilityDocumentElement {
    collector?.incrementElementCount()

    var node = AccessibilityDocumentElement()

    func read<T>(_ key: AXKeys, _ value: T?) -> T?? {
      guard keys.contains(key) else {
        return nil
      }
      collector?.incrementAttributeFetchCount(forKey: key.rawValue)
      return .some(value)
    }

    // Frame is always read since it is used by multiple keys.
    collector?.incrementAttributeFetchCount(forKey: AXKeys.frame.rawValue)
    let frame = snapshot.frame

    var role: String?
    var rawRole: String?
    if keys.contains(.role) {
      collector?.incrementAttributeFetchCount(forKey: AXKeys.role.rawValue)
      rawRole = snapshot.role
      node.role = .some(rawRole)
    }
    if keys.contains(.type) {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: AXKeys.type.rawValue)
        rawRole = snapshot.role
      }
      // accessibilityRole may be prefixed with "AX"; strip it to match the
      // SimulatorBridge implementation.
      role = rawRole.map(AXRoleVocabulary.normalizeRole)
    }

    node.label = read(.label, snapshot.label)
    if keys.contains(.frame) {
      node.axFrame = .some(NSStringFromRect(frame))
    }
    node.value = read(.value, snapshot.value)
    node.identifier = read(.uniqueID, snapshot.identifier)

    if keys.contains(.type) {
      node.type = .some(role)
    }

    node.title = read(.title, snapshot.title)
    if keys.contains(.frameDict) {
      collector?.incrementAttributeFetchCount(forKey: AXKeys.frameDict.rawValue)
      node.frame = .some(AccessibilityFrame(frame))
    }
    node.help = read(.help, snapshot.help)
    node.enabled = read(.enabled, snapshot.isEnabled)
    node.customActions = read(.customActions, snapshot.customActionNames)
    node.roleDescription = read(.roleDescription, snapshot.roleDescription)
    node.subrole = read(.subrole, snapshot.subrole)
    node.contentRequired = read(.contentRequired, snapshot.isRequired)
    node.pid = read(.pid, Int64(snapshot.pid))
    if keys.contains(.traits) {
      collector?.incrementAttributeFetchCount(forKey: AXKeys.traits.rawValue)
      node.traits = .some(snapshot.traits)
    }
    node.expanded = read(.expanded, snapshot.isExpanded)
    node.placeholder = read(.placeholder, snapshot.placeholder)
    node.hidden = read(.hidden, snapshot.isHidden)
    node.focused = read(.focused, snapshot.isFocused)
    if keys.contains(.interactable) {
      collector?.incrementAttributeFetchCount(forKey: AXKeys.interactable.rawValue)
      node.interactable = .some(snapshot.hittability.flatMap { interactable(for: $0, frame: frame) })
      node.explainedBy = snapshot.explainedBy.map { explanation in
        AccessibilityElementRef(
          type: explanation.role.map(AXRoleVocabulary.normalizeRole),
          identifier: explanation.identifier,
          label: explanation.label,
          frame: AccessibilityFrame(explanation.frame),
          pid: Int64(explanation.pid)
        )
      }
    }

    return node
  }

  /// The caller reports an explicit null when the backend cannot answer hittability at all — never
  /// derived from `enabled`, which would confuse "disabled" with "unreachable". Reasons accumulate
  /// rather than short-circuit: an element is often blocked more than one way.
  private static func interactable(
    for hittability: AXHittability,
    frame: NSRect
  ) -> AccessibilityInteractable? {
    var reasons: [AccessibilityInteractable.Reason] = []
    if frame.width == 0 || frame.height == 0 {
      reasons.append(.zeroSize)
    }
    if hittability.isHidden {
      reasons.append(.hidden)
    }
    if hittability.isEnabled == false {
      reasons.append(.disabled)
    }
    if hittability.isUserInteractionEnabled == false {
      reasons.append(.userInteractionDisabled)
    }

    let hittablePoint = hittability.hittablePoint.flatMap(AccessibilityPoint.init)
    if !hittability.isHittable {
      // No reachable point at all. This attribute cannot say whether the element is covered, clipped,
      // transparent or handled by a relative — naming the cause needs the `occludedBy` hit-test.
      reasons.append(.notHittable)
    }

    guard reasons.isEmpty else {
      return .blocked(reasons: reasons.mostSpecificFirst)
    }

    // Hittable but no point: the read carried no point (a wire that answers hittability without one),
    // not an unreachable element — so nil, not `notHittable`.
    guard let hittablePoint else {
      return nil
    }

    // Actionable even when the point is not the centre: for a partially covered element the centre is
    // exactly what fails.
    return .actionable(at: hittablePoint)
  }

  /// Wraps `nodeElement` with the two traversal-level concerns the pure core omits: recording the
  /// element's pid in `seenPids` (so remote-content hit-testing can skip processes already present in the
  /// main tree) and, when `.isRemote` is requested, tagging the node's provenance — `true` for nodes
  /// discovered by remote grid hit-testing, `false` for the main-tree traversal. `.isRemote` is not in
  /// `AXKeys.defaultSet`, so a default response is unchanged by the decorator.
  static func decoratedElement(
    forSnapshot snapshot: AXElementSnapshot,
    keys: Set<AXKeys>,
    collector: AccessibilityProfilingCollector?,
    seenPids: SeenPIDs?,
    isRemote: Bool
  ) -> AccessibilityDocumentElement {
    var node = nodeElement(forSnapshot: snapshot, keys: keys, collector: collector)
    seenPids?.insert(snapshot.pid)
    if keys.contains(.isRemote) {
      collector?.incrementAttributeFetchCount(forKey: AXKeys.isRemote.rawValue)
      node.isRemote = .some(isRemote)
    }
    return node
  }

  // MARK: - Recursion

  // Flat output lists every node separately, so `children` stays nil.
  private static func flatRecursiveDescription(
    fromSnapshot snapshot: AXElementSnapshot,
    keys: Set<AXKeys>,
    collector: AccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [AccessibilityDocumentElement] {
    var values: [AccessibilityDocumentElement] = [
      decoratedElement(forSnapshot: snapshot, keys: keys, collector: collector, seenPids: seenPids, isRemote: false)
    ]
    for child in snapshot.children {
      values.append(contentsOf: flatRecursiveDescription(fromSnapshot: child, keys: keys, collector: collector, seenPids: seenPids))
    }
    return values
  }

  // Returns the element as a single nested node carrying its serialized subtree.
  private static func nestedRecursiveDescription(
    fromSnapshot snapshot: AXElementSnapshot,
    keys: Set<AXKeys>,
    collector: AccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [AccessibilityDocumentElement] {
    var childrenValues: [AccessibilityDocumentElement] = []
    for child in snapshot.children {
      childrenValues.append(contentsOf: nestedRecursiveDescription(fromSnapshot: child, keys: keys, collector: collector, seenPids: seenPids))
    }
    var values = decoratedElement(forSnapshot: snapshot, keys: keys, collector: collector, seenPids: seenPids, isRemote: false)
    values.children = childrenValues
    return [values]
  }
}

/// What a serialization reports — which keys, and whether descendants nest under their parent or follow
/// it in one flat list — and so what a read for it must fetch.
struct AXSerialization: Equatable {
  let keys: Set<AXKeys>
  let nested: Bool

  init(keys: Set<AXKeys>, nested: Bool) {
    self.keys = keys
    self.nested = nested
  }

  init(_ options: AccessibilityRequestOptions) {
    self.init(keys: options.serializationKeys, nested: options.nestedFormat)
  }

  /// The read this serialization consumes, to `depth`.
  func readPlan(depth: AXReadPlan.Depth) -> AXReadPlan {
    AXReadPlan(keys: keys, depth: depth)
  }
}
