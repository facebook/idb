/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The translator's own role numbering: the value of `BridgeAXTranslatorAttribute.role`, decoded from the
/// framework rather than observed.
///
/// A separate scheme from `XCUIElementType` — `button` is 2 here and 9 there. Recovered from
/// `-[AXPMacPlatformElement _convertTranslatorResponse:forAttribute:]`, which switches on attribute 45
/// through a 21-entry jump table; 18 of the entries load an AppKit `NSAccessibility*Role` global and three
/// are string constants AppKit has no name for. 0 and anything above 21 are not roles. The guest has no
/// name table for either roles or subroles — only the macOS side carries one, which is why reading the
/// simulator runtime alone does not answer this.
///
/// Two entries are coarser than the element a reader would name: `checkBox` covers toggles and
/// `textField` covers search fields. `BridgeAXTranslatorSubrole` carries the refinement.
@frozen public enum BridgeAXTranslatorRole: Int, Sendable, CaseIterable {
  case application = 1
  case button = 2
  case checkBox = 3
  case genericElement = 4
  case group = 5
  case heading = 6
  case image = 7
  case link = 8
  case radioButton = 9
  case scrollArea = 10
  case scrollBar = 11
  case tabGroup = 12
  case slider = 13
  case staticText = 14
  case textField = 15
  case webArea = 16
  case textArea = 17
  case splitter = 18
  case popUpButton = 19
  case sheet = 20
  case grid = 21

  /// Apple's `AX*` role constant with the prefix dropped (`Button`), how every other role reaches a
  /// serializer. Most coincide with an `XCUIElementType` name; `GenericElement`, `Heading`, `ScrollArea`,
  /// `WebArea` and `TextArea` have no counterpart there. `Heading` has none at all, which is why XCTest
  /// types such an element as `Any`.
  public var name: String {
    switch self {
    case .application: "Application"
    case .button: "Button"
    case .checkBox: "CheckBox"
    case .genericElement: "GenericElement"
    case .group: "Group"
    case .heading: "Heading"
    case .image: "Image"
    case .link: "Link"
    case .radioButton: "RadioButton"
    case .scrollArea: "ScrollArea"
    case .scrollBar: "ScrollBar"
    case .tabGroup: "TabGroup"
    case .slider: "Slider"
    case .staticText: "StaticText"
    case .textField: "TextField"
    case .webArea: "WebArea"
    case .textArea: "TextArea"
    case .splitter: "Splitter"
    case .popUpButton: "PopUpButton"
    case .sheet: "Sheet"
    case .grid: "Grid"
    }
  }
}

/// The translator's subrole numbering: the value of `BridgeAXTranslatorAttribute.subrole`, decoded the
/// same way as the roles.
///
/// A subrole refines a role rather than replacing it, and for two of these the refinement is the name a
/// caller actually wants: a toggle is role `checkBox` with subrole `switch`, and a search field is role
/// `textField` with subrole `searchField`. So where a subrole is identified it is the better answer.
///
/// The producer is `-[AXPTranslator_iOS _processSubroleAttributeRequest:traits:error:]` in the guest, a
/// trait decision tree: `kAXSearchFieldTrait` -> 1, `kAXTabButtonTrait` -> 2, `kAXToggleTrait` -> 3,
/// `kAXMapTrait` -> 4, `kAXSecureTextFieldTrait` -> 5. The names come from the macOS copy of the framework,
/// where attribute 51 switches through a jump table of AppKit `NSAccessibility*Subrole` globals.
@frozen public enum BridgeAXTranslatorSubrole: Int, Sendable, CaseIterable {
  case searchField = 1
  case tabButton = 2
  case `switch` = 3
  case mapArea = 4
  case secureTextField = 5
  case mapItem = 6

  /// Apple's `AX*` subrole constant with the prefix dropped (`Switch`).
  public var name: String {
    switch self {
    case .searchField: "SearchField"
    case .tabButton: "TabButton"
    case .switch: "Switch"
    case .mapArea: "MapArea"
    case .secureTextField: "SecureTextField"
    case .mapItem: "MapItem"
    }
  }
}
