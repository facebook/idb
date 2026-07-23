/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import Foundation

/// The accessibility attribute + action surface the serializer, translation
/// request, dispatcher, element handle, and facade depend on, expressed in plain
/// value types.
///
/// Production instances are Objective-C runtime adapters around an opaque private
/// framework object. Test doubles can conform directly without loading that
/// framework.
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
  func axCustomActionNames() -> [String]
  func axActionNames() -> [String]
  func axTraits() -> [String]?
  func axChildren() -> [FBAXPlatformElement]
  func axPerformPress() -> Bool
  func axScroll(_ direction: FBAccessibilityScrollDirection)
  func axSetValue(_ value: Any?)

  /// The pid of the backing translation object (0 when absent).
  var axTranslationPid: pid_t { get }
  /// Sets the backing translation object's bridge-delegate token (no-op when absent).
  func axSetBridgeDelegateToken(_ token: String?)
}

extension FBAXRuntimePlatformElement: FBAXPlatformElement {
  func axFrame() -> NSRect { frame() }
  func axRole() -> String? { role() }
  func axLabel() -> String? { label() }
  func axValue() -> Any? { value() }
  func axIdentifier() -> String? { identifier() }
  func axTitle() -> String? { title() }
  func axHelp() -> String? { help() }
  func axRoleDescription() -> String? { roleDescription() }
  func axSubrole() -> String? { subrole() }
  func axPlaceholderValue() -> String? { placeholderValue() }
  func axIsEnabled() -> Bool { isEnabled() }
  func axIsRequired() -> Bool { isRequired() }
  func axIsExpanded() -> Bool { isExpanded() }
  func axIsHidden() -> Bool { isHidden() }
  func axIsFocused() -> Bool { isFocused() }
  func axCustomActionNames() -> [String] { customActionNames() }
  func axActionNames() -> [String] { actionNames() }
  func axTraits() -> [String]? { traits() }
  func axChildren() -> [FBAXPlatformElement] { children() }
  func axPerformPress() -> Bool { performPress() }

  func axScroll(_ direction: FBAccessibilityScrollDirection) {
    switch direction {
    case .down:
      scrollDown()
    case .up:
      scrollUp()
    case .left:
      scrollLeft()
    case .right:
      scrollRight()
    case .visible:
      scrollToVisible()
    @unknown default:
      break
    }
  }

  func axSetValue(_ value: Any?) { setValue(value) }

  var axTranslationPid: pid_t { translationPID() }
  func axSetBridgeDelegateToken(_ token: String?) { setBridgeDelegateToken(token) }
}
