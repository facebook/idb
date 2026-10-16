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

/// Decodes the `XC_kAXXC*` attribute dictionaries the axbridge guest returns into snapshots.
///
/// The guest has already fetched everything its traversal asked for, so decoding takes the whole tree in
/// one pass; there is no plan to honour on this side.
enum AXBridgeSnapshotDecoder {

  /// Decodes a nested attribute-dictionary tree, tagging every node with the owning application's pid.
  static func snapshot(fromTree node: [String: Any], pid: pid_t) -> AXElementSnapshot {
    let childNodes = (node[AXWire.Node.children.rawValue] as? [[String: Any]]) ?? []
    return snapshot(fromNode: node, pid: pid, children: childNodes.map { snapshot(fromTree: $0, pid: pid) })
  }

  /// Decodes one node, ignoring any children it carries.
  static func snapshot(fromNode node: [String: Any], pid: pid_t, children: [AXElementSnapshot] = []) -> AXElementSnapshot {
    let attributes = Attributes(node)
    let explanation = (node[AXWire.Node.explainedBy.rawValue] as? [String: Any]).map { snapshot(fromNode: $0, pid: pid) }
    return AXElementSnapshot(
      frame: attributes.frame,
      pid: pid,
      role: attributes.role,
      label: attributes.string(AXWire.Node.label),
      value: AccessibilityAttributeValue(node[AXWire.Node.value.rawValue]),
      stringValue: node[AXWire.Node.value.rawValue] as? String,
      identifier: attributes.string(AXWire.Node.identifier),
      // Answered only by a read through the translator's vocabulary, which is the only one that fetches
      // it. Absent on every other read, so those still report `enabled` as unknown rather than
      // fabricating it.
      isEnabled: attributes.bool(AXWire.Node.isEnabled),
      customActionNames: [],
      isRequired: false,
      traits: attributes.traits,
      isExpanded: false,
      isHidden: false,
      isFocused: false,
      hittability: attributes.hittability,
      explainedBy: explanation,
      children: children
    )
  }
}

// MARK: - Attributes

extension AXBridgeSnapshotDecoder {

  /// Typed reads over one node's dictionary.
  private struct Attributes {
    let node: [String: Any]

    init(_ node: [String: Any]) {
      self.node = node
    }

    var frame: NSRect {
      guard let raw = node[AXWire.Node.frame.rawValue] else { return .zero }
      // The daemon serializes the frame as a CGRect dictionary representation (mirroring the CGPoint
      // dictionary `requestElementAtPoint:` consumes); tolerate an `NSValue` rect as a fallback.
      var rect = CGRect.zero
      if let dict = raw as? NSDictionary,
        CGRectMakeWithDictionaryRepresentation(Self.restoringNonFinite(dict) as CFDictionary, &rect)
      {
        return rect
      }
      if let value = raw as? NSValue {
        return value.rectValue
      }
      return .zero
    }

    /// JSON has no infinity or NaN, so the guest sends null for a non-finite coordinate (routine for an
    /// off-screen or still-laying-out element). Restored to infinity so
    /// `CGRectMakeWithDictionaryRepresentation` does not fail and read the whole rect as zero;
    /// `AccessibilityFrame` then nulls each non-finite edge independently.
    private static func restoringNonFinite(_ dictionary: NSDictionary) -> NSDictionary {
      guard dictionary.allValues.contains(where: { $0 is NSNull }) else {
        return dictionary
      }
      let restored = NSMutableDictionary(dictionary: dictionary)
      for (key, value) in dictionary where value is NSNull {
        restored[key] = NSNumber(value: Double.infinity)
      }
      return restored
    }

    var role: String? {
      // Resolution order: a named automation type (skipping `Any`, which means "untyped"), then the element
      // type, then translator subrole before role (the refinement is the name a caller wants), then a
      // class-name string. `Any` and stringified numbers come last so nothing identifying is discarded.
      let automationName = elementTypeName(AXWire.Node.automationType)
      let identifying =
        (automationName == AXRoleVocabulary.untypedName ? nil : automationName)
        ?? elementTypeName(AXWire.Node.elementType)
        ?? translatorSubroleName
        ?? translatorRoleName
        ?? className(AXWire.Node.elementType)
      return identifying
        ?? automationName
        ?? string(AXWire.Node.automationType)
        ?? string(AXWire.Node.elementType)
    }

    var traits: [String]? {
      let bitmask = node[AXWire.Node.xcTraits.rawValue] ?? node[AXWire.Node.traits.rawValue]
      guard let bitmask = bitmask as? NSNumber else {
        return nil
      }
      return AXExtractTraits(bitmask.uint64Value)
    }

    /// Nil when the read did not ask whether a touch reaches the element.
    var hittability: AXHittability? {
      guard let isHittable = bool(AXWire.Node.isVisible) else {
        return nil
      }
      return AXHittability(
        isHittable: isHittable,
        isHidden: false,
        isEnabled: bool(AXWire.Node.isEnabled),
        isUserInteractionEnabled: bool(AXWire.Node.userInteractionEnabled),
        hittablePoint: point(AXWire.Node.visiblePoint)
      )
    }

    /// A boolean attribute, or nil when the read did not carry it — which is the case for every read that
    /// did not ask for it, and is what makes "not requested" distinguishable from a definite `false`.
    func bool(_ key: AXWire.Node) -> Bool? {
      (node[key.rawValue] as? NSNumber)?.boolValue
    }

    /// A point attribute, as the guest emits it: an `X`/`Y` dictionary, tolerating an `NSValue` as the
    /// frame does. The accessibility server's `(-1, -1)` "nothing is reachable" sentinel is carried through
    /// unchanged — turning it into an absent point is the serializer's job, where it becomes the absence
    /// of the actionable case rather than a coordinate anyone has to recognise.
    func point(_ key: AXWire.Node) -> CGPoint? {
      guard let raw = node[key.rawValue] else { return nil }
      var point = CGPoint.zero
      if let dictionary = raw as? NSDictionary,
        CGPointMakeWithDictionaryRepresentation(dictionary as CFDictionary, &point)
      {
        return point
      }
      if let value = raw as? NSValue {
        return value.pointValue
      }
      return nil
    }

    // The daemon returns most attributes as strings, but the element-type attributes can arrive as
    // numbers; coerce so callers see a stable `String?`.
    func string(_ key: AXWire.Node) -> String? {
      guard let raw = node[key.rawValue] else { return nil }
      if let string = raw as? String { return string }
      return String(describing: raw)
    }

    /// The name for the translator's subrole integer, or nil when the wire carries none or it is not
    /// identified.
    private var translatorSubroleName: String? {
      guard let raw = (node[AXWire.Node.translatorSubrole.rawValue] as? NSNumber)?.intValue else {
        return nil
      }
      return BridgeAXTranslatorSubrole(rawValue: raw)?.name
    }

    /// The role name for the translator's own role integer, or nil when the wire carries none or the
    /// integer is not in the table.
    private var translatorRoleName: String? {
      guard let raw = (node[AXWire.Node.translatorRole.rawValue] as? NSNumber)?.intValue else {
        return nil
      }
      return BridgeAXTranslatorRole(rawValue: raw)?.name
    }

    /// The attribute when it arrived as a class name; nil when it arrived as a number.
    private func className(_ key: AXWire.Node) -> String? {
      node[key.rawValue] as? String
    }

    /// The readable name for an `XCUIElementType`-valued attribute, or `nil` when the attribute is
    /// absent or its raw number is not a known type (letting the caller fall back to the raw value).
    private func elementTypeName(_ key: AXWire.Node) -> String? {
      guard let number = (node[key.rawValue] as? NSNumber)?.intValue else { return nil }
      return AXRoleVocabulary.name(forElementType: number)
    }
  }
}
