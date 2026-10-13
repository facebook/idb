/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

internal import AXRuntime
import FBControlCore
import Foundation

// Each trait paired with the name AXRuntime gives it - the constant minus its
// `AXTrait` prefix, in bit order, which is the order names are reported in.
private let axTraitNames: [(AXTraits, String)] = [
  (.button, "Button"),
  (.link, "Link"),
  (.image, "Image"),
  (.selected, "Selected"),
  (.playsSound, "PlaysSound"),
  (.keyboardKey, "KeyboardKey"),
  (.staticText, "StaticText"),
  (.summaryElement, "SummaryElement"),
  (.notEnabled, "NotEnabled"),
  (.updatesFrequently, "UpdatesFrequently"),
  (.searchField, "SearchField"),
  (.startsMediaSession, "StartsMediaSession"),
  (.adjustable, "Adjustable"),
  (.allowsDirectInteraction, "AllowsDirectInteraction"),
  (.causesPageTurn, "CausesPageTurn"),
  (.tabBar, "TabBar"),
  (.header, "Header"),
  (.webContent, "WebContent"),
  (.textEntry, "TextEntry"),
  (.pickerElement, "PickerElement"),
  (.radioButton, "RadioButton"),
  (.isEditing, "IsEditing"),
  (.launchIcon, "LaunchIcon"),
  (.statusBarElement, "StatusBarElement"),
  (.secureTextField, "SecureTextField"),
  (.inactive, "Inactive"),
  (.footer, "Footer"),
  (.backButton, "BackButton"),
  (.tabButton, "TabButton"),
  (.autoCorrectCandidate, "AutoCorrectCandidate"),
  (.deleteKey, "DeleteKey"),
  (.selectionDismissesItem, "SelectionDismissesItem"),
  (.visited, "Visited"),
  (.scrollable, "Scrollable"),
  (.spacer, "Spacer"),
  (.tableIndex, "TableIndex"),
  (.map, "Map"),
  (.textOperationsAvailable, "TextOperationsAvailable"),
  (.draggable, "Draggable"),
  (.gesturePracticeRegion, "GesturePracticeRegion"),
  (.popupButton, "PopupButton"),
  (.allowsNativeSliding, "AllowsNativeSliding"),
  (.mathEquation, "MathEquation"),
  (.containedByTable, "ContainedByTable"),
  (.containedByList, "ContainedByList"),
  (.touchContainer, "TouchContainer"),
  (.supportsZoom, "SupportsZoom"),
  (.textArea, "TextArea"),
  (.bookContent, "BookContent"),
  (.containedByLandmark, "ContainedByLandmark"),
  (.folderIcon, "FolderIcon"),
  (.readOnly, "ReadOnly"),
  (.menuItem, "MenuItem"),
  (.toggle, "Toggle"),
  (.ignoreItemChooser, "IgnoreItemChooser"),
  (.supportsTrackingDetail, "SupportsTrackingDetail"),
  (.alert, "Alert"),
  (.containedByFieldset, "ContainedByFieldset"),
  (.allowsLayoutChangeInStatusBar, "AllowsLayoutChangeInStatusBar"),
]

private let axTraitToName: [UInt64: String] =
  Dictionary(uniqueKeysWithValues: axTraitNames.map { ($0.0.rawValue, $0.1) })

/// Mapping from single-bit accessibility trait values to their names.
func AXTraitToNameMap() -> [UInt64: String] {
  axTraitToName
}

/// The names of the traits present in `traitBitmask`, in bit order so the same mask always reads the
/// same: "None" for an empty mask, and "Unknown" last when bits remain that no known trait accounts for.
public func AXExtractTraits(_ traitBitmask: UInt64) -> [String] {
  guard traitBitmask != 0 else {
    return ["None"]
  }
  var remaining = traitBitmask
  var extracted: [String] = []
  for (trait, name) in axTraitNames where (remaining & trait.rawValue) == trait.rawValue {
    remaining -= trait.rawValue
    extracted.append(name)
  }
  if remaining != 0 {
    extracted.append("Unknown")
  }
  return extracted
}
