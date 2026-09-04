/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// Adapts the `XC_kAXXC*` dictionaries returned by the axbridge guest to `FBAXPlatformElement`.
final class FBAXBridgePlatformElement: FBAXPlatformElement {
  private let attributes: [String: Any]
  private let childElements: [FBAXBridgePlatformElement]
  private let pid: pid_t

  init(attributes: [String: Any], children: [FBAXBridgePlatformElement], pid: pid_t) {
    self.attributes = attributes
    self.childElements = children
    self.pid = pid
  }

  func axFrame() -> NSRect {
    guard let raw = attributes[FBAXWire.Node.frame.rawValue] else { return .zero }
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
  /// `FBAccessibilityFrame` then nulls each non-finite edge independently.
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

  func axRole() -> String? {
    // Resolution order: a named automation type (skipping `Any`, which means "untyped"), then the element
    // type, then translator subrole before role (the refinement is the name a caller wants), then a
    // class-name string. `Any` and stringified numbers come last so nothing identifying is discarded.
    let automationName = elementTypeName(FBAXWire.Node.automationType.rawValue)
    let identifying =
      (automationName == FBAXRoleVocabulary.untypedName ? nil : automationName)
      ?? elementTypeName(FBAXWire.Node.elementType.rawValue)
      ?? translatorSubroleName()
      ?? translatorRoleName()
      ?? className(FBAXWire.Node.elementType.rawValue)
    return identifying
      ?? automationName
      ?? stringAttribute(FBAXWire.Node.automationType.rawValue)
      ?? stringAttribute(FBAXWire.Node.elementType.rawValue)
  }

  func axLabel() -> String? { stringAttribute(FBAXWire.Node.label.rawValue) }
  func axValue() -> Any? { attributes[FBAXWire.Node.value.rawValue] }
  func axIdentifier() -> String? { stringAttribute(FBAXWire.Node.identifier.rawValue) }
  func axTitle() -> String? { nil }
  func axHelp() -> String? { nil }
  func axRoleDescription() -> String? { nil }
  func axSubrole() -> String? { nil }
  func axPlaceholderValue() -> String? { nil }
  // Answered only by a read through the translator's vocabulary, which is the only one that fetches it.
  // Absent on every other read, so those still report `enabled` as unknown rather than fabricating it.
  func axIsEnabled() -> Bool? { boolAttribute(FBAXWire.Node.isEnabled.rawValue) }
  func axIsRequired() -> Bool { false }
  func axIsExpanded() -> Bool { false }
  func axIsHidden() -> Bool { false }
  func axIsFocused() -> Bool { false }

  func axIsHittable() -> Bool? { boolAttribute(FBAXWire.Node.isVisible.rawValue) }
  func axHittablePoint() -> CGPoint? { pointAttribute(FBAXWire.Node.visiblePoint.rawValue) }
  func axCentrePoint() -> CGPoint? { pointAttribute(FBAXWire.Node.centerPoint.rawValue) }
  func axIsUserInteractionEnabled() -> Bool? { boolAttribute(FBAXWire.Node.userInteractionEnabled.rawValue) }

  /// What the guest's hit-test at this element's centre found, when the read asked it to look. Nil when
  /// it did not ask, when the element is reachable, or when nothing answered.
  func axExplainedBy() -> FBAXPlatformElement? {
    guard let attributes = self.attributes[FBAXWire.Node.explainedBy.rawValue] as? [String: Any] else {
      return nil
    }
    return FBAXBridgePlatformElement(attributes: attributes, children: [], pid: pid)
  }
  func axCustomActionNames() -> [String] { [] }
  func axActionNames() -> [String] { [] }
  func axTraits() -> [String]? { nil }
  func axChildren() -> [FBAXPlatformElement] { childElements }

  var axTranslationPid: pid_t { pid }
  func axSetBridgeDelegateToken(_ token: String?) {}

  /// A boolean attribute, or nil when the read did not carry it — which is the case for every read that
  /// did not ask for it, and is what makes "not requested" distinguishable from a definite `false`.
  private func boolAttribute(_ key: String) -> Bool? {
    (attributes[key] as? NSNumber)?.boolValue
  }

  /// A point attribute, as the guest emits it: an `X`/`Y` dictionary, tolerating an `NSValue` as the
  /// frame's accessor does. The accessibility server's `(-1, -1)` "nothing is reachable" sentinel is
  /// carried through unchanged — turning it into an absent point is the serializer's job, where it
  /// becomes the absence of the actionable case rather than a coordinate anyone has to recognise.
  private func pointAttribute(_ key: String) -> CGPoint? {
    guard let raw = attributes[key] else { return nil }
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
  private func stringAttribute(_ key: String) -> String? {
    guard let raw = attributes[key] else { return nil }
    if let string = raw as? String { return string }
    return String(describing: raw)
  }

  /// The name for the translator's subrole integer, or nil when the wire carries none or it is not
  /// identified.
  private func translatorSubroleName() -> String? {
    guard let raw = (attributes[FBAXWire.Node.translatorSubrole.rawValue] as? NSNumber)?.intValue else {
      return nil
    }
    return FBAXRoleVocabulary.name(forTranslatorSubrole: raw)
  }

  /// The role name for the translator's own role integer, or nil when the wire carries none or the
  /// integer is not in the table.
  private func translatorRoleName() -> String? {
    guard let raw = (attributes[FBAXWire.Node.translatorRole.rawValue] as? NSNumber)?.intValue else {
      return nil
    }
    return FBAXRoleVocabulary.name(forTranslatorRole: raw)
  }

  /// The attribute when it arrived as a class name; nil when it arrived as a number.
  private func className(_ key: String) -> String? {
    attributes[key] as? String
  }

  /// The readable name for an `XCUIElementType`-valued attribute, or `nil` when the attribute is
  /// absent or its raw number is not a known type (letting the caller fall back to the raw value).
  private func elementTypeName(_ key: String) -> String? {
    guard let number = (attributes[key] as? NSNumber)?.intValue else { return nil }
    return FBAXRoleVocabulary.name(forElementType: number)
  }
}
