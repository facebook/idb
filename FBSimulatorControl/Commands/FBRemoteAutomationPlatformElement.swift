/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// An `FBAXPlatformElement` backed by a remote-automation `fetchAttributes` result, so the remote
/// element tree feeds the same serializer as the legacy AX path. It conforms to the read-only
/// `FBAXPlatformElement` and not `FBAXWritableElement`: the remote projection cannot be acted on, so
/// element actions are kept off it by the type system rather than by silently no-op'd accessors.
final class FBRemoteAutomationPlatformElement: FBAXPlatformElement {
  private let attributes: [String: Any]
  private let childElements: [FBRemoteAutomationPlatformElement]
  private let pid: pid_t

  init(attributes: [String: Any], children: [FBRemoteAutomationPlatformElement], pid: pid_t) {
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

  /// A frame dictionary with each JSON null restored to the non-finite number it stands for.
  ///
  /// The guest cannot send a non-finite coordinate — JSON has neither infinity nor NaN — so it emits
  /// null instead, and an element that is off-screen or still being laid out reports one routinely.
  /// Undoing that here is what lets the rest of the read treat the value as the host's own element
  /// already does: `FBAccessibilityFrame` normalizes each edge independently, so the unreadable one
  /// becomes null and the others survive.
  ///
  /// The alternative is losing the whole rectangle to one member, since
  /// `CGRectMakeWithDictionaryRepresentation` sends a number selector to every value and a null would
  /// crash it. That reports an off-screen element as sitting at the origin with no size — which reads
  /// as a real position rather than an absent one, and is worse than reporting nothing.
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
    // The daemon reports the automation/element type as an `XCUIElementType` raw value; map it to a
    // readable name (e.g. 9 -> "Button") so the serialized role is legible rather than a bare number.
    // An already-string value (or an unmapped number) passes through unchanged.
    elementTypeName(FBAXWire.Node.automationType.rawValue)
      ?? elementTypeName(FBAXWire.Node.elementType.rawValue)
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
  func axIsEnabled() -> Bool { true }
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
    return FBRemoteAutomationPlatformElement(attributes: attributes, children: [], pid: pid)
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

  /// The readable name for an `XCUIElementType`-valued attribute, or `nil` when the attribute is
  /// absent or its raw number is not a known type (letting the caller fall back to the raw value).
  private func elementTypeName(_ key: String) -> String? {
    guard let number = (attributes[key] as? NSNumber)?.intValue else { return nil }
    return FBAXRoleVocabulary.name(forElementType: number)
  }
}
