/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

internal import AccessibilityPlatformTranslation
import AppKit
import FBControlCore
import FBSimulatorControl
import Foundation
import ObjectiveC

/// A translator element as `AXElementSnapshot.read` sees it: one accessor per attribute, each a round trip
/// to the simulator. Actions live in `AXWritableElement`.
///
/// `AXPMacPlatformElement` is a private-framework class tests cannot subclass; the protocol admits test
/// doubles without unsafe casts.
protocol AXPlatformElement: AnyObject {
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
  func axIsEnabled() -> Bool?
  func axIsRequired() -> Bool
  func axIsExpanded() -> Bool
  func axIsHidden() -> Bool
  func axIsFocused() -> Bool
  func axCustomActionNames() -> [String]
  func axActionNames() -> [String]
  func axTraits() -> [String]?
  func axChildren() -> [AXPlatformElement]
  /// The values of many NSAccessibility attributes, keyed by name, in one round trip. An attribute with no
  /// value is absent.
  func axMultipleAttributes(_ names: [String]) -> [String: Any]

  /// The pid of the backing translation object (0 when absent).
  var axTranslationPid: pid_t { get }
  /// The backing translation object, which a raw read names the element by; nil when absent.
  var axTranslationReference: AXTranslationReference? { get }
  /// Sets the backing translation object's bridge-delegate token (no-op when absent).
  func axSetBridgeDelegateToken(_ token: String?)
}

/// A translator element's identity on the wire: what a raw request names, and what an element's children
/// answer with. `AXPTranslationObject` is a private-framework class tests cannot subclass; the protocol admits
/// test doubles.
protocol AXTranslationReference: AnyObject {
  var pid: pid_t { get }
  var objectID: UInt64 { get }
  // Spelled as the private header imports it, so `AXPTranslationObject` conforms as declared.
  // swiftlint:disable:next implicitly_unwrapped_optional
  var bridgeDelegateToken: String! { get set }
}

extension AXPTranslationObject: AXTranslationReference {}

/// What an element is read and acted on through: the translator's platform element where a read already
/// has one, or the element's translation, from which the platform element is built only when something
/// acts on the element. A raw read hands out translations, so reading builds no platform elements.
enum AXElementHandle {
  case element(AXPlatformElement)
  case translation(AXTranslationReference)

  var translation: AXTranslationReference? {
    switch self {
    case let .element(element): element.axTranslationReference
    case let .translation(translation): translation
    }
  }

  var pid: pid_t {
    switch self {
    case let .element(element): element.axTranslationPid
    case let .translation(translation): translation.pid
    }
  }
}

/// The mutating action surface — press, scroll, set-value — layered on the read surface.
/// Only the legacy CoreSimulator element (`AXPMacPlatformElement`) and its test double
/// perform these, so a caller that acts on an element (`AccessibilityElement`) demands
/// this refinement and the type system keeps actions off the read-only axbridge tree.
protocol AXWritableElement: AXPlatformElement {
  func axPerformPress() -> Bool
  func axPerformCustomAction(named name: String) -> Bool
  func axScroll(_ direction: AccessibilityScrollDirection)
  func axSetValue(_ value: Any?)
}

func invokeAccessibilityCustomAction(_ action: NSAccessibilityCustomAction) -> Bool {
  if let handler = action.handler {
    return handler()
  }
  guard
    let target = action.target,
    let selector = action.selector
  else {
    return false
  }
  let object = target as AnyObject
  guard
    object.responds(to: selector),
    let cls = object_getClass(object),
    let method = class_getInstanceMethod(cls, selector)
  else {
    return false
  }
  let implementation = method_getImplementation(method)
  var returnType = [CChar](repeating: 0, count: 16)
  method_getReturnType(method, &returnType, returnType.count)
  let returnTypeName = String(
    decoding: returnType.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
    as: UTF8.self
  )
  let argumentCount = method_getNumberOfArguments(method)
  if argumentCount == 3 {
    guard let argumentType = method_copyArgumentType(method, 2) else {
      return false
    }
    defer { free(argumentType) }
    guard String(cString: argumentType) == "@" else {
      return false
    }
  }
  switch (argumentCount, returnTypeName) {
  case (2, "B"), (2, "c"):
    typealias Action = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(implementation, to: Action.self)(object, selector)
  case (3, "B"), (3, "c"):
    typealias Action = @convention(c) (AnyObject, Selector, NSAccessibilityCustomAction) -> Bool
    return unsafeBitCast(implementation, to: Action.self)(object, selector, action)
  case (2, "v"):
    typealias Action = @convention(c) (AnyObject, Selector) -> Void
    unsafeBitCast(implementation, to: Action.self)(object, selector)
    return true
  case (3, "v"):
    typealias Action = @convention(c) (AnyObject, Selector, NSAccessibilityCustomAction) -> Void
    unsafeBitCast(implementation, to: Action.self)(object, selector, action)
    return true
  default:
    return false
  }
}

extension AXPMacPlatformElement: AXPlatformElement {
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
  func axIsEnabled() -> Bool? { isAccessibilityEnabled() }
  func axIsRequired() -> Bool { isAccessibilityRequired() }
  func axIsExpanded() -> Bool { isAccessibilityExpanded() }
  func axIsHidden() -> Bool { isAccessibilityHidden() }
  func axIsFocused() -> Bool { isAccessibilityFocused() }
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
    return AXExtractTraits(result.uint64Value)
  }

  func axChildren() -> [AXPlatformElement] {
    (accessibilityChildren() ?? []).compactMap { $0 as? AXPlatformElement }
  }

  func axMultipleAttributes(_ names: [String]) -> [String: Any] {
    // Read by message: `accessibilityMultipleAttributes:` is private to `AXPMacPlatformElement`. It sends one
    // multiple-attribute request through the bridge for every attribute it does not answer locally.
    let selector = NSSelectorFromString("accessibilityMultipleAttributes:")
    guard responds(to: selector),
      let raw = perform(selector, with: names as NSArray)?.takeUnretainedValue() as? NSDictionary
    else {
      return [:]
    }
    var values: [String: Any] = [:]
    for (key, value) in raw {
      guard let key = key as? String, !(value is NSNull) else { continue }
      values[key] = value
    }
    return values
  }

  var axTranslationPid: pid_t { translation?.pid ?? 0 }
  var axTranslationReference: AXTranslationReference? { translation }
  func axSetBridgeDelegateToken(_ token: String?) { translation?.bridgeDelegateToken = token }
}

extension AXPMacPlatformElement: AXWritableElement {
  func axPerformPress() -> Bool { accessibilityPerformPress() }

  func axPerformCustomAction(named name: String) -> Bool {
    guard let action = accessibilityCustomActions()?.first(where: { $0.name == name }) else {
      return false
    }
    return invokeAccessibilityCustomAction(action)
  }

  func axScroll(_ direction: AccessibilityScrollDirection) {
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
