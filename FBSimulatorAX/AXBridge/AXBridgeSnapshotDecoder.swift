/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation

/// Decodes the `BridgeAXNode` trees the axbridge guest returns into snapshots.
///
/// The guest has already fetched everything its traversal asked for, so decoding takes the whole tree in
/// one pass; there is no plan to honour on this side.
enum AXBridgeSnapshotDecoder {

  /// Decodes a nested node tree, tagging every node with the owning application's pid.
  static func snapshot(fromTree node: BridgeAXNode, pid: pid_t) -> AXElementSnapshot {
    snapshot(fromNode: node, pid: pid, children: (node.children ?? []).map { snapshot(fromTree: $0, pid: pid) })
  }

  /// Decodes one node, ignoring any children it carries.
  static func snapshot(fromNode node: BridgeAXNode, pid: pid_t, children: [AXElementSnapshot] = []) -> AXElementSnapshot {
    AXElementSnapshot(
      frame: frame(of: node),
      pid: pid,
      role: role(of: node),
      label: node.label?.text,
      value: node.value.map(AccessibilityAttributeValue.init(scalar:)),
      stringValue: node.value?.string,
      identifier: node.identifier?.text,
      // Answered only by a read through the translator's vocabulary, which is the only one that fetches
      // it. Absent on every other read, so those still report `enabled` as unknown rather than
      // fabricating it.
      isEnabled: node.isEnabled,
      customActionNames: [],
      isRequired: false,
      traits: (node.xcTraits ?? node.traits).map(AXExtractTraits),
      isExpanded: false,
      isHidden: false,
      isFocused: false,
      hittability: hittability(of: node),
      explainedBy: node.explainedBy.map { snapshot(fromNode: $0, pid: pid) },
      children: children
    )
  }
}

// MARK: - Attributes

extension AXBridgeSnapshotDecoder {

  /// JSON has no infinity or NaN, so the guest sends null for a non-finite coordinate (routine for an
  /// off-screen or still-laying-out element). Restored to infinity here; `AccessibilityFrame` then nulls
  /// each non-finite edge independently. A node that carries no frame is at the origin with no size.
  private static func frame(of node: BridgeAXNode) -> NSRect {
    guard let frame = node.frame else { return .zero }
    return NSRect(x: frame.x ?? .infinity, y: frame.y ?? .infinity, width: frame.width ?? .infinity, height: frame.height ?? .infinity)
  }

  /// Resolution order: a named automation type (skipping `Any`, which means "untyped"), then the element
  /// type, then translator subrole before role (the refinement is the name a caller wants), then a
  /// class-name string. `Any` and stringified numbers come last so nothing identifying is discarded.
  private static func role(of node: BridgeAXNode) -> String? {
    let automationName = node.automationType?.integer.flatMap { AXRoleVocabulary.name(forElementType: Int($0)) }
    let identifying =
      (automationName == AXRoleVocabulary.untypedName ? nil : automationName)
      ?? node.elementType?.integer.flatMap { AXRoleVocabulary.name(forElementType: Int($0)) }
      ?? node.translatorSubrole.flatMap { BridgeAXTranslatorSubrole(rawValue: $0)?.name }
      ?? node.translatorRole.flatMap { BridgeAXTranslatorRole(rawValue: $0)?.name }
      ?? node.elementType?.string
    return identifying
      ?? automationName
      ?? node.automationType?.text
      ?? node.elementType?.text
  }

  /// Nil when the read did not ask whether a touch reaches the element.
  ///
  /// The point is carried as the accessibility server reported it, its `(-1, -1)` "nothing is reachable"
  /// sentinel included: turning that into an absent point is the serializer's job.
  private static func hittability(of node: BridgeAXNode) -> AXHittability? {
    guard let isHittable = node.isVisible else {
      return nil
    }
    return AXHittability(
      isHittable: isHittable,
      isHidden: false,
      isEnabled: node.isEnabled,
      isUserInteractionEnabled: node.userInteractionEnabled,
      hittablePoint: node.visiblePoint.flatMap { point in
        guard let x = point.x, let y = point.y else { return nil }
        return CGPoint(x: x, y: y)
      }
    )
  }
}

extension BridgeAXScalar {

  /// The attribute as text: strings as they are, other kinds as Foundation describes them, so an
  /// element-type number reads as it always has.
  var text: String {
    switch self {
    case let .string(string): string
    case let .bool(bool): NSNumber(value: bool).stringValue
    case let .integer(integer): String(integer)
    case let .number(number): NSNumber(value: number).stringValue
    }
  }

  var string: String? {
    guard case let .string(string) = self else { return nil }
    return string
  }

  var integer: Int64? {
    guard case let .integer(integer) = self else { return nil }
    return integer
  }
}

extension AccessibilityAttributeValue {

  init(scalar: BridgeAXScalar) {
    switch scalar {
    case let .string(string): self = .string(string)
    case let .bool(bool): self = .bool(bool)
    case let .integer(integer): self = .int(integer)
    case let .number(number): self = .double(number)
    }
  }
}
