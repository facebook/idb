/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import AccessibilityPlatformTranslation
import AppKit
import FBControlCore
import Foundation

/// The read-only accessibility attribute + traversal surface the serializer, translation
/// request, dispatcher, element handle, and facade depend on, expressed in plain value
/// types. Element actions live in `FBAXWritableElement`, so a tree that can only be read —
/// the remote-automation projection — conforms here without pretending it can act.
///
/// `AXPMacPlatformElement` is a private-framework class the unit tests cannot
/// subclass, so they previously flowed message-responding doubles through the code
/// via `unsafeBitCast(... to: AXPMacPlatformElement.self)`. Routing the production
/// code through this protocol instead lets both the real element (which conforms via
/// the adapter extension below) and the test doubles participate with no unsafe
/// casts. Expressing it as an adapter — rather than mirroring the overlay's own
/// signatures — also keeps the `NSAccessibility.Role`/`.Action` overlay types out of
/// callers, and folds in the `objc_msgSend`-forcing `as AnyObject` reads, the
/// `accessibilityAttributeValue:` traits reflection, and the children casting.
protocol FBAXPlatformElement: AnyObject {
  func axFrame() -> NSRect
  func axRole() -> String?
  func axLabel() -> String?
  func axValue() -> Any?
  func axIdentifier() -> String?
  func axTitle() -> String?
  func axHelp() -> String?
  func axRoleDescription() -> String?
  func axSubrole() -> String?
  func axPlaceholderValue() -> String?
  func axIsEnabled() -> Bool
  func axIsRequired() -> Bool
  func axIsExpanded() -> Bool
  func axIsHidden() -> Bool
  func axIsFocused() -> Bool

  /// Whether the accessibility server believes a touch reaches this element at all, the point it
  /// believes a touch reaches, the element's own centre, and whether the view takes touches.
  ///
  /// Optional throughout, because "cannot answer" is a real answer here and has to be distinguishable
  /// from a definite `false`: these come from `XC_kAXXC*` attributes that only the guest-backed wires
  /// carry, and the legacy `AXPMacPlatformElement` path has no NSAccessibility counterpart for any of
  /// them. A backend that answers nil reports `interactable` as an explicit null rather than fabricating
  /// a judgement from attributes it never read.
  func axIsHittable() -> Bool?
  func axHittablePoint() -> CGPoint?
  func axCentrePoint() -> CGPoint?
  func axIsUserInteractionEnabled() -> Bool?
  func axCustomActionNames() -> [String]
  func axActionNames() -> [String]
  func axTraits() -> [String]?
  func axChildren() -> [FBAXPlatformElement]

  /// The pid of the backing translation object (0 when absent).
  var axTranslationPid: pid_t { get }
  /// Sets the backing translation object's bridge-delegate token (no-op when absent).
  func axSetBridgeDelegateToken(_ token: String?)
}

/// The mutating action surface — press, scroll, set-value — layered on the read surface.
/// Only the legacy CoreSimulator element (`AXPMacPlatformElement`) and its test double
/// perform these, so a caller that acts on an element (`FBAccessibilityElement`) demands
/// this refinement and the type system keeps actions off the read-only remote tree.
protocol FBAXWritableElement: FBAXPlatformElement {
  func axPerformPress() -> Bool
  func axScroll(_ direction: FBAccessibilityScrollDirection)
  func axSetValue(_ value: Any?)
}

extension AXPMacPlatformElement: FBAXPlatformElement {
  func axFrame() -> NSRect { accessibilityFrame() }
  func axRole() -> String? { accessibilityRole()?.rawValue }
  func axLabel() -> String? { accessibilityLabel() }
  func axValue() -> Any? { accessibilityValue() }
  func axIdentifier() -> String? { accessibilityIdentifier() }
  func axTitle() -> String? { accessibilityTitle() }
  func axHelp() -> String? { accessibilityHelp() }
  func axRoleDescription() -> String? { accessibilityRoleDescription() }
  func axSubrole() -> String? { accessibilitySubrole()?.rawValue }
  func axPlaceholderValue() -> String? { accessibilityPlaceholderValue() }
  func axIsEnabled() -> Bool { isAccessibilityEnabled() }
  func axIsRequired() -> Bool { isAccessibilityRequired() }
  func axIsExpanded() -> Bool { isAccessibilityExpanded() }
  func axIsHidden() -> Bool { isAccessibilityHidden() }
  func axIsFocused() -> Bool { isAccessibilityFocused() }

  // NSAccessibility has no counterpart for any of these — `isAccessibilityHidden` is a self-declared
  // property, not "something is on top of me" — so this backend declines to answer rather than guessing.
  func axIsHittable() -> Bool? { nil }
  func axHittablePoint() -> CGPoint? { nil }
  func axCentrePoint() -> CGPoint? { nil }
  func axIsUserInteractionEnabled() -> Bool? { nil }
  func axCustomActionNames() -> [String] { (accessibilityCustomActions() ?? []).map { $0.name } }
  func axActionNames() -> [String] {
    // Read by message: the instance `accessibilityActionNames` is shadowed by a
    // class member of the same name on `AXPMacPlatformElement` in this context.
    let selector = NSSelectorFromString("accessibilityActionNames")
    guard responds(to: selector),
      let raw = perform(selector)?.takeUnretainedValue() as? NSArray
    else {
      return []
    }
    return raw.compactMap { $0 as? String }
  }

  func axTraits() -> [String]? {
    // `accessibilityAttributeValue:` is a Swift-unavailable deprecated NSAccessibility
    // API, so read AXTraits by message.
    let selector = NSSelectorFromString("accessibilityAttributeValue:")
    guard responds(to: selector) else {
      return nil
    }
    guard let result = perform(selector, with: "AXTraits")?.takeUnretainedValue() as? NSNumber else {
      return nil
    }
    return Array(AXExtractTraits(result.uint64Value))
  }

  func axChildren() -> [FBAXPlatformElement] {
    (accessibilityChildren() ?? []).compactMap { $0 as? FBAXPlatformElement }
  }

  var axTranslationPid: pid_t { translation?.pid ?? 0 }
  func axSetBridgeDelegateToken(_ token: String?) { translation?.bridgeDelegateToken = token }
}

extension AXPMacPlatformElement: FBAXWritableElement {
  func axPerformPress() -> Bool { accessibilityPerformPress() }

  func axScroll(_ direction: FBAccessibilityScrollDirection) {
    switch direction {
    case .down:
      performScrollDownByPageAction()
    case .up:
      performScrollUpByPageAction()
    case .left:
      performScrollLeftByPageAction()
    case .right:
      performScrollRightByPageAction()
    case .visible:
      performScrollToVisible()
    }
  }

  func axSetValue(_ value: Any?) { setAccessibilityValue(value) }
}
