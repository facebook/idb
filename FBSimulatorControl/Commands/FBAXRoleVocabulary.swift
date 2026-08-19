/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The AX role/element-type vocabulary shared by the two UI-automation reader backends: the
/// `XCUIElementType` raw-value → readable-name map the remote adapter resolves numeric types through,
/// the `AX`-prefix normalization the serializer applies before comparing role names, and the set of
/// roles the `.interactable` filter keeps. Centralizing them keeps the remote adapter's numeric-type
/// names and the serializer's role handling from drifting out of one shared spelling.
enum FBAXRoleVocabulary {

  private static let axPrefix = "AX"

  /// The name `XCUIElementType` 0 maps to — the automation type reporting that it has no type for an
  /// element, rather than a type of its own. Named because it is a *successful* lookup: a caller
  /// resolving a type has to be able to tell "answered, and the answer is no type" from a miss.
  static let untypedName = "Any"

  /// The readable name for an `XCUIElementType` raw value (e.g. 9 -> "Button"), or `nil` when the number
  /// is not a known type — letting the caller fall back to the raw value.
  static func name(forElementType rawValue: Int) -> String? {
    elementTypeNames[rawValue]
  }

  /// A role name with the accessibility `AX` prefix stripped (`AXButton` -> `Button`), matching the
  /// SimulatorBridge role spelling. A name without the prefix passes through unchanged.
  static func normalizeRole(_ role: String) -> String {
    role.hasPrefix(axPrefix) ? String(role.dropFirst(axPrefix.count)) : role
  }

  /// Whether a role — in either its raw or `AX`-prefixed spelling — is one the `.interactable` filter keeps.
  static func isInteractable(role: String) -> Bool {
    interactableRoles.contains(normalizeRole(role))
  }

  /// Actionable `XCUIElementType`/role names (the `AX` prefix stripped) kept by `.interactable`.
  private static let interactableRoles: Set<String> = [
    "Button", "Cell", "TextField", "SecureTextField", "SearchField", "Switch", "Toggle", "Link",
    "MenuItem", "Slider", "CheckBox", "RadioButton", "SegmentedControl", "Stepper", "PopUpButton",
    "Picker", "PickerWheel", "Tab", "Key", "DisclosureTriangle",
  ]

  /// `XCUIElementType` raw values -> readable names, mirroring Apple's enum (not linked host-side).
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
