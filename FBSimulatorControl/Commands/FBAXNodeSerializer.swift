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
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter = .all
  ) -> [FBAccessibilityDocumentElement] {
    element.axSetBridgeDelegateToken(token)
    if nestedFormat {
      return nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter)
    }
    return flatRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter)
  }

  static func formattedDescription(
    ofElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?
  ) -> FBAccessibilityDocumentElement {
    element.axSetBridgeDelegateToken(token)
    var node = decoratedElement(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil, isRemote: false)
    guard nestedFormat else {
      return node
    }
    // The target is never filtered: the caller named this element by point or marker, so answering with
    // nothing — or with one of its descendants hoisted into its place — would not answer the question.
    // Building it directly, rather than taking the first result of a filtered walk over it, is what lets
    // the target always be reported and always carry a `children` array.
    var children: [FBAccessibilityDocumentElement] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      children.append(
        contentsOf: nestedRecursiveDescription(
          fromElement: child, token: token, keys: keys, collector: collector,
          coverageGrid: coverageGrid, seenPids: nil, filter: .all
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
  /// `collector` and `coverageGrid` are pure side-channels intrinsic to the attribute-read pass: the
  /// collector tallies each fetch (and the coverage grid marks the frame it reads) without altering the
  /// returned node — proven by `testNodeDictionaryIsCollectorNeutral`. They stay in the core because the
  /// tallies (and the exact `nil`-key coverage read) are a byte-for-byte consequence of the read order,
  /// so the order below is deliberate and must not be rearranged. The traversal-level concerns the core
  /// omits — seen-pid dedup and the `is_remote` provenance tag — live in `decoratedElement`.
  static func nodeElement(
    forElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?
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

    // Frame is always computed since it is used by multiple keys and the coverage grid.
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

    // Mark frame in coverage grid (for non-Application elements).
    if let coverageGrid {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: nil)
        rawRole = element.axRole()
      }
      let isApplication = rawRole == "AXApplication" || rawRole == "Application"
      if !isApplication {
        coverageGrid.markFilled(with: frame)
      }
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

    return node
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
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    isRemote: Bool
  ) -> FBAccessibilityDocumentElement {
    var node = nodeElement(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid)
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
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter
  ) -> [FBAccessibilityDocumentElement] {
    var values: [FBAccessibilityDocumentElement] = []
    if passes(element, filter: filter) {
      values.append(decoratedElement(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, isRemote: false))
    }
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      values.append(contentsOf: flatRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter))
    }
    return values
  }

  // Returns the element as a single nested node, or — when it is filtered out — its kept descendants
  // hoisted, for the caller to splice into the nearest kept ancestor.
  private static func nestedRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter
  ) -> [FBAccessibilityDocumentElement] {
    var childrenValues: [FBAccessibilityDocumentElement] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      childrenValues.append(contentsOf: nestedRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter))
    }
    guard passes(element, filter: filter) else {
      return childrenValues
    }
    var values = decoratedElement(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, isRemote: false)
    values.children = childrenValues
    return [values]
  }

  // MARK: - Filter

  /// Whether an element is kept under `filter`. `.interactable` keeps elements carrying a label, an
  /// identifier, or an actionable role — dropping unlabeled structural containers.
  private static func passes(_ element: FBAXPlatformElement, filter: FBAccessibilityElementFilter) -> Bool {
    switch filter {
    case .all:
      return true
    case .interactable:
      if let label = element.axLabel(), !label.isEmpty { return true }
      if let identifier = element.axIdentifier(), !identifier.isEmpty { return true }
      if let role = element.axRole(), FBAXRoleVocabulary.isInteractable(role: role) { return true }
      return false
    }
  }
}
