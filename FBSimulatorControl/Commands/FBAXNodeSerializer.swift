/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import Foundation

/// Serializes an `FBAXPlatformElement` tree into the typed accessibility schema. Values are kept
/// compatible with the SimulatorBridge output downstream consumers parse.
///
/// Each attribute is read into a statically-typed field; `axValue()` is genuinely `Any` and is
/// classified into `FBAccessibilityAttributeValue` at the read site.
enum FBAXNodeSerializer {

  // MARK: - Entry points

  static func recursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [FBAccessibilityDocumentElement] {
    element.axSetBridgeDelegateToken(token)
    if nestedFormat {
      return nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, seenPids: seenPids)
    }
    return flatRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, seenPids: seenPids)
  }

  static func formattedDescription(
    ofElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?
  ) -> FBAccessibilityDocumentElement {
    element.axSetBridgeDelegateToken(token)
    var node = decoratedElement(forElement: element, token: token, keys: keys, collector: collector, seenPids: nil, isRemote: false)
    guard nestedFormat else {
      return node
    }
    // The target's descendants are built as a subtree of their own, rather than by walking the target
    // itself, so the target is always reported and always carries a `children` array — a filtered walk
    // rooted at the target could drop or replace it. The caller filters these children afterwards.
    var children: [FBAccessibilityDocumentElement] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      children.append(
        contentsOf: nestedRecursiveDescription(
          fromElement: child, token: token, keys: keys, collector: collector,
          seenPids: nil
        )
      )
    }
    node.children = children
    return node
  }

  // MARK: - Node

  /// Builds the node for a single element over `keys`.
  ///
  /// An attribute is read only when requested, and the result records that: a requested attribute is
  /// `.some(value-or-nil)` and an unrequested one stays `nil`, which is what lets the encodings emit an
  /// explicit null for the former and nothing at all for the latter.
  ///
  /// The collector tallies each fetch in read order, so the order below is load-bearing for the profile
  /// and must not be rearranged. Seen-pid dedup and the `is_remote` tag live in `decoratedElement`.
  static func nodeElement(
    forElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?
  ) -> FBAccessibilityDocumentElement {
    // The token must always be set so that the right callback is called.
    element.axSetBridgeDelegateToken(token)

    collector?.incrementElementCount()

    var node = FBAccessibilityDocumentElement()

    func read<T>(_ key: FBAXKeys, _ value: @autoclosure () -> T?) -> T?? {
      guard keys.contains(key) else {
        return nil
      }
      collector?.incrementAttributeFetchCount(forKey: key.rawValue)
      return .some(value())
    }

    // Frame is always computed since it is used by multiple keys.
    collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frame.rawValue)
    let frame = element.axFrame()

    var role: String?
    var rawRole: String?
    if keys.contains(.role) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.role.rawValue)
      rawRole = element.axRole()
      node.role = .some(rawRole)
    }
    if keys.contains(.type) {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: FBAXKeys.type.rawValue)
        rawRole = element.axRole()
      }
      // accessibilityRole may be prefixed with "AX"; strip it to match the
      // SimulatorBridge implementation.
      role = rawRole.map(FBAXRoleVocabulary.normalizeRole)
    }

    node.label = read(.label, element.axLabel())
    if keys.contains(.frame) {
      node.axFrame = .some(NSStringFromRect(frame))
    }
    node.value = read(.value, FBAccessibilityAttributeValue(element.axValue()))
    node.identifier = read(.uniqueID, element.axIdentifier())

    if keys.contains(.type) {
      node.type = .some(role)
    }

    node.title = read(.title, element.axTitle())
    if keys.contains(.frameDict) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frameDict.rawValue)
      node.frame = .some(FBAccessibilityFrame(frame))
    }
    node.help = read(.help, element.axHelp())
    node.enabled = read(.enabled, element.axIsEnabled())
    node.customActions = read(.customActions, element.axCustomActionNames())
    node.roleDescription = read(.roleDescription, element.axRoleDescription())
    node.subrole = read(.subrole, element.axSubrole())
    node.contentRequired = read(.contentRequired, element.axIsRequired())
    node.pid = read(.pid, Int64(element.axTranslationPid))
    if keys.contains(.traits) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.traits.rawValue)
      node.traits = .some(element.axTraits())
    }
    node.expanded = read(.expanded, element.axIsExpanded())
    node.placeholder = read(.placeholder, element.axPlaceholderValue())
    node.hidden = read(.hidden, element.axIsHidden())
    node.focused = read(.focused, element.axIsFocused())
    if keys.contains(.interactable) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.interactable.rawValue)
      node.interactable = .some(interactable(forElement: element, frame: frame))
      node.explainedBy = element.axExplainedBy().map { explanation in
        FBAccessibilityElementRef(
          type: explanation.axRole().map(FBAXRoleVocabulary.normalizeRole),
          identifier: explanation.axIdentifier(),
          label: explanation.axLabel(),
          frame: FBAccessibilityFrame(explanation.axFrame()),
          pid: Int64(explanation.axTranslationPid)
        )
      }
    }

    return node
  }

  /// Nil (an explicit null downstream) when the backend cannot answer hittability at all — never
  /// derived from `enabled`, which would confuse "disabled" with "unreachable". Reasons accumulate
  /// rather than short-circuit: an element is often blocked more than one way.
  private static func interactable(
    forElement element: FBAXPlatformElement,
    frame: NSRect
  ) -> FBAccessibilityInteractable? {
    guard let hittable = element.axIsHittable() else {
      return nil
    }

    var reasons: [FBAccessibilityInteractable.Reason] = []
    if frame.width == 0 || frame.height == 0 {
      reasons.append(.zeroSize)
    }
    if element.axIsHidden() {
      reasons.append(.hidden)
    }
    if element.axIsEnabled() == false {
      reasons.append(.disabled)
    }
    if element.axIsUserInteractionEnabled() == false {
      reasons.append(.userInteractionDisabled)
    }

    let hittablePoint = element.axHittablePoint().flatMap(FBAccessibilityPoint.init)
    if !hittable {
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
  /// `FBAXKeys.defaultSet`, so a default response is unchanged by the decorator.
  static func decoratedElement(
    forElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    seenPids: SeenPIDs?,
    isRemote: Bool
  ) -> FBAccessibilityDocumentElement {
    var node = nodeElement(forElement: element, token: token, keys: keys, collector: collector)
    seenPids?.insert(element.axTranslationPid)
    if keys.contains(.isRemote) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.isRemote.rawValue)
      node.isRemote = .some(isRemote)
    }
    return node
  }

  // MARK: - Recursion

  // Flat output lists every node separately, so `children` stays nil.
  private static func flatRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [FBAccessibilityDocumentElement] {
    var values: [FBAccessibilityDocumentElement] = [
      decoratedElement(forElement: element, token: token, keys: keys, collector: collector, seenPids: seenPids, isRemote: false)
    ]
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      values.append(contentsOf: flatRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, seenPids: seenPids))
    }
    return values
  }

  // Returns the element as a single nested node carrying its serialized subtree.
  private static func nestedRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    seenPids: SeenPIDs?
  ) -> [FBAccessibilityDocumentElement] {
    var childrenValues: [FBAccessibilityDocumentElement] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      childrenValues.append(contentsOf: nestedRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, seenPids: seenPids))
    }
    var values = decoratedElement(forElement: element, token: token, keys: keys, collector: collector, seenPids: seenPids, isRemote: false)
    values.children = childrenValues
    return [values]
  }
}
