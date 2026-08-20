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

  /// The role name for an integer in the translator's own role numbering, or nil when the integer is not
  /// one of the 21 in the table.
  ///
  /// Most names coincide with an `XCUIElementType`; `GenericElement`, `Heading`, `ScrollArea`, `WebArea`
  /// and `TextArea` have no counterpart there, so a caller matching against `XCUIElementType` will not
  /// recognise them.
  static func name(forTranslatorRole rawValue: Int) -> String? {
    translatorRoleNames[rawValue]
  }

  /// The name for a translator subrole integer, or nil when that integer has not been identified.
  ///
  /// Worth preferring over the role where both are present: the subrole is what distinguishes a switch
  /// from a plain check box and a search field from a plain text field.
  static func name(forTranslatorSubrole rawValue: Int) -> String? {
    translatorSubroleNames[rawValue]
  }

  /// A role name with the accessibility `AX` prefix stripped (`AXButton` -> `Button`), matching the
  /// SimulatorBridge role spelling, and legacy-mangled Swift class names demangled
  /// (`_TtGC7SwiftUI15CellHostingView…` -> `CellHostingView`). A name needing neither passes
  /// through unchanged.
  static func normalizeRole(_ role: String) -> String {
    let stripped = role.hasPrefix(axPrefix) ? String(role.dropFirst(axPrefix.count)) : role
    return FBSwiftClassNameDemangler.demangle(stripped)
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

  /// The translator's own role numbering, decoded from the framework rather than observed.
  ///
  /// A separate scheme from `XCUIElementType` — `Button` is 2 here and 9 there. The names are Apple's
  /// `AX*` role constants with the prefix dropped, matching how every other role reaches the serializer.
  ///
  /// Recovered from `-[AXPMacPlatformElement _convertTranslatorResponse:forAttribute:]`, which switches
  /// on attribute 45 through a 21-entry jump table; 18 of the entries load an AppKit `NSAccessibility*Role`
  /// global and three are string constants AppKit has no name for. 0 and anything above 21 are not roles.
  ///
  /// Two entries are coarser than the element a reader would name: `CheckBox` covers toggles and
  /// `TextField` covers search fields. `translatorSubroleNames` carries the refinement.
  ///
  /// `Heading` has no `XCUIElementType` counterpart at all, which is why XCTest types such an element as
  /// `Any` — there is no name in that vocabulary to map it to.
  private static let translatorRoleNames: [Int: String] = [
    1: "Application", 2: "Button", 3: "CheckBox", 4: "GenericElement", 5: "Group",
    6: "Heading", 7: "Image", 8: "Link", 9: "RadioButton", 10: "ScrollArea",
    11: "ScrollBar", 12: "TabGroup", 13: "Slider", 14: "StaticText", 15: "TextField",
    16: "WebArea", 17: "TextArea", 18: "Splitter", 19: "PopUpButton", 20: "Sheet",
    21: "Grid",
  ]

  /// The translator's subrole numbering, decoded the same way as the roles.
  ///
  /// A subrole refines a role rather than replacing it, and for two of these the refinement is the name a
  /// caller actually wants: a toggle is role `CheckBox` with subrole `Switch`, and a search field is role
  /// `TextField` with subrole `SearchField`. Both refined names are `XCUIElementType` members and are in
  /// `interactableRoles`; neither bare role is. So where a subrole is identified it is the better answer.
  ///
  /// Derivation, for anyone extending this. The producer is
  /// `-[AXPTranslator_iOS _processSubroleAttributeRequest:traits:error:]` in the guest's
  /// `AccessibilityPlatformTranslation`, a trait decision tree: `kAXSearchFieldTrait` -> 1,
  /// `kAXTabButtonTrait` -> 2, `kAXToggleTrait` -> 3, `kAXMapTrait` -> 4, `kAXSecureTextFieldTrait` -> 5.
  /// The names come from the macOS copy of the same framework, where
  /// `-[AXPMacPlatformElement _convertTranslatorResponse:forAttribute:]` switches attribute 51 through a
  /// jump table whose entries load AppKit `NSAccessibility*Subrole` globals; resolving those globals in a
  /// loaded image gives the strings. The guest has no name table for either roles or subroles — only the
  /// macOS side carries one, which is why reading the simulator runtime alone does not answer this.
  private static let translatorSubroleNames: [Int: String] = [
    1: "SearchField", 2: "TabButton", 3: "Switch", 4: "MapArea",
    5: "SecureTextField", 6: "MapItem",
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
