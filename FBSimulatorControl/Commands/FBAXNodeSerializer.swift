/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import Foundation

/// Serializes an `AXPMacPlatformElement` tree into the typed JSON emitted by the
/// accessibility commands. The values mirror the old SimulatorBridge implementation
/// for downstream compatibility.
///
/// Driven entirely from Swift (`FBAXTranslationRequest` and its remote-content
/// code), so it is a plain Swift namespace returning a typed element. Each attribute
/// is read into a statically-typed field, so no scalar is round-tripped through an
/// untyped `NSNumber`. `axValue()` is the one exception — it is genuinely `Any` — and
/// is classified into the closed `FBAccessibilityAttributeValue` set at the read site.
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
    // itself, so that the target is always reported and always carries a `children` array. A caller who
    // named an element by point or marker asked about *that* element; answering with nothing — or with
    // one of its descendants hoisted into its place — would not answer the question, which is what a
    // filtered walk rooted at the target would do. The caller filters these children afterwards.
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
  /// `collector` is a pure side-channel intrinsic to the attribute-read pass: it tallies each fetch
  /// without altering the returned node — proven by `testNodeDictionaryIsCollectorNeutral`. It stays in
  /// the core because the tallies are a byte-for-byte consequence of the read order, so the order below
  /// is deliberate and must not be rearranged. The traversal-level concerns the core omits — seen-pid
  /// dedup and the `is_remote` provenance tag — live in `decoratedElement`.
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

    // Reads an attribute only when it was requested, tallying the fetch exactly as the ObjC macro did.
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

    // Role is used by multiple keys and needs processing. Check Role first to
    // assign rawRole, then Type can derive from it.
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

    // Legacy values that mirror SimulatorBridge.
    node.label = read(.label, element.axLabel())
    if keys.contains(.frame) {
      node.axFrame = .some(NSStringFromRect(frame))
    }
    node.value = read(.value, FBAccessibilityAttributeValue(element.axValue()))
    node.identifier = read(.uniqueID, element.axIdentifier())

    // Synthetic values.
    if keys.contains(.type) {
      node.type = .some(role)
    }

    // New values.
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

  /// Whether an element can be acted on, derived from the attributes just read.
  ///
  /// Nil — an explicit null downstream — when the backend cannot answer. Hittability is checked first
  /// because a backend that answers nothing carries no hittability attribute, so the guard catches it
  /// before any other attribute is consulted. Falling back to `enabled` would confuse "disabled" with
  /// "unreachable", which is the distinction this key exists for.
  ///
  /// Reasons accumulate rather than short-circuit, because an element is often blocked more than one way
  /// and a caller told only the first would fix it and hit the next.
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
      // No reachable point at all. Which of covered, clipped, transparent or handled by a relative it is
      // cannot be told from this attribute — naming the cause needs the hit-test `occludedBy` pays for.
      reasons.append(.notHittable)
    }

    guard reasons.isEmpty else {
      return .blocked(reasons: reasons.mostSpecificFirst)
    }

    // Reachable, nothing against it, and no point to act at. "The read carried no point" and "the server
    // reports no reachable point" are different facts, and `hittable` being false already caught the
    // second. The `axIsHittable()` guard assumes a backend answering hittability answers the rest, which
    // holds while a read fetches the attributes as a group. Where a wire answers hittability and carries
    // no point, returning `notHittable` would call a reachable element unreachable and give a reason.
    guard let hittablePoint else {
      return nil
    }

    // A reachable point makes the element actionable, whether or not that point is its centre. For a
    // partially covered element the centre is exactly what fails and this is the point that does not, so
    // reporting it is the difference between a caller succeeding and a caller being told it cannot act on
    // something it demonstrably can. Nothing is lost by not flagging the divergence: a caller that cares
    // can compare `at` against the frame it already has.
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

  // Non-hierarchical (flat) output: frames are relative to the root, as in SimulatorBridge. A flat node
  // carries no children — the traversal lists every node separately — which is why `children` stays nil.
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
