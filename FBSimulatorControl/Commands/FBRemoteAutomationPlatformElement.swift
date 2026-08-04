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
/// element tree feeds the same serializer as the legacy AX path. Read-only: the action accessors
/// (`axPerformPress`/`axScroll`/`axSetValue`) are no-ops here — remote element actions are wired in
/// their own later commits.
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
    // A frame member can arrive as JSON null: an off-screen or still-settling element reports a
    // non-finite coordinate, which the guest emits as null (JSON has no infinity or NaN).
    // `CGRectMakeWithDictionaryRepresentation` sends a number selector to every member, so a null one
    // crashes it — and a frame with a non-numeric member has no usable geometry regardless.
    if let dict = raw as? NSDictionary, dict.allValues.allSatisfy({ $0 is NSNumber }),
      CGRectMakeWithDictionaryRepresentation(dict as CFDictionary, &rect)
    {
      return rect
    }
    if let value = raw as? NSValue {
      return value.rectValue
    }
    return .zero
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
  func axCustomActionNames() -> [String] { [] }
  func axActionNames() -> [String] { [] }
  func axTraits() -> [String]? { nil }
  func axChildren() -> [FBAXPlatformElement] { childElements }
  func axPerformPress() -> Bool { false }
  func axScroll(_ direction: FBAccessibilityScrollDirection) {}
  func axSetValue(_ value: Any?) {}

  var axTranslationPid: pid_t { pid }
  func axSetBridgeDelegateToken(_ token: String?) {}

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
    return Self.elementTypeNames[number]
  }

  /// `XCUIElementType` raw values → readable names, mirroring Apple's enum (not linked host-side).
  private static let elementTypeNames: [Int: String] = [
    0: "Any", 1: "Other", 2: "Application", 3: "Group", 4: "Window", 5: "Sheet", 6: "Drawer",
    7: "Alert", 8: "Dialog", 9: "Button", 10: "RadioButton", 11: "RadioGroup", 12: "CheckBox",
    13: "DisclosureTriangle", 14: "PopUpButton", 15: "ComboBox", 16: "MenuButton", 17: "ToolbarButton",
    18: "Popover", 19: "Keyboard", 20: "Key", 21: "NavigationBar", 22: "TabBar", 23: "TabGroup",
    24: "Toolbar", 25: "StatusBar", 26: "Table", 27: "TableRow", 28: "TableColumn", 29: "Outline",
    30: "OutlineRow", 31: "Browser", 32: "CollectionView", 33: "Slider", 34: "PageIndicator",
    35: "ProgressIndicator", 36: "ActivityIndicator", 37: "SegmentedControl", 38: "Picker",
    39: "PickerWheel", 40: "Switch", 41: "Toggle", 42: "Link", 43: "Image", 44: "Icon",
    45: "SearchField", 46: "ScrollView", 47: "ScrollBar", 48: "StaticText", 49: "TextField",
    50: "SecureTextField", 51: "DatePicker", 52: "TextView", 53: "Menu", 54: "MenuItem", 55: "MenuBar",
    56: "MenuBarItem", 57: "Map", 58: "WebView", 59: "IncrementArrow", 60: "DecrementArrow",
    61: "Timeline", 62: "RatingIndicator", 63: "ValueIndicator", 64: "SplitGroup", 65: "Splitter",
    66: "RelevanceIndicator", 67: "ColorWell", 68: "HelpTag", 69: "Matte", 70: "DockItem", 71: "Ruler",
    72: "RulerMarker", 73: "Grid", 74: "LevelIndicator", 75: "Cell", 76: "LayoutArea", 77: "LayoutItem",
    78: "Handle", 79: "Stepper", 80: "Tab", 81: "TouchBar", 82: "StatusItem",
  ]
}
