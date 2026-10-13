/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The attribute vocabulary `AXPTranslator` answers in — a separate namespace from XCTest's
/// `XC_kAXXCAttribute*` names, with separate server-side handlers; an element handle from one is not
/// accepted by the other. The host reads it over CoreSimulatorBridge's accessibility service and the
/// guest reads it in-process, so both name what they ask for here.
///
/// Raw values are the enum's own indices, recovered from `__AXPAttributeToString` in the guest
/// `AccessibilityPlatformTranslation` binary (0–129 is the bound both it and
/// `-[AXPTranslator_iOS attributeFromRequest:]` enforce); identical on the 26.4, 26.5 and 27.0 runtimes.
/// The macOS copy of the framework uses the same numbering.
///
/// **Declared is not fetchable.** Only the name each index binds to is verified. The translator raises on
/// a value it cannot convert, and an uncaught raise takes the reader down, so anything added to a fetch
/// list needs a run against a real screen first.
@frozen public enum BridgeAXTranslatorAttribute: Int, Sendable, CaseIterable {
  /// The sentinel the table starts at, and what the translator answers for an index it does not know.
  case undefined = 0
  case activationPoint = 1
  case assistiveTechnologyFocused = 2
  case attributedLabel = 3
  case attributedStringForRange = 4
  case boundsForRange = 5
  case bundleIdentifier = 6
  case className = 7
  case children = 8
  case childrenInNavigationOrder = 9
  case childrenContainerGroupingBehaviorHasOverridingParentDelegate = 10
  case parentDiscardsChildrenContainerGroupingBehavior = 11
  case contextId = 12
  case customActions = 13
  case customRotors = 14
  case customRotorData = 15
  case customRotorSearchResult = 16
  case equivalenceTag = 17
  case firstContainedElement = 18
  case focusedElement = 19
  case focusedOpaqueElement = 20
  case frame = 21
  /// Heading depth. Guest attribute 2180.
  case headingLevel = 22
  case help = 23
  case horizontalScrollBar = 24
  case identifier = 25
  /// Whether the element is an accessibility element in its own right rather than a container. Guest attribute
  /// 2016; the translator's role handler branches on it to choose `Group` over `GenericElement`.
  case isElement = 26
  /// No counterpart in the `XC_kAXXCAttribute*` namespace.
  case isEnabled = 27
  case isFocused = 28
  case isOpaqueElementProvider = 29
  case isSelected = 30
  /// Whether the element is still live. Guest attribute 2056.
  case isValid = 31
  case isVisible = 32
  case label = 33
  case lastContainedElement = 34
  case moveFocusToNextOpaqueElement = 35
  case moveFocusToPreviousOpaqueElement = 36
  case nextContentSibling = 37
  case numberOfCharacters = 38
  case opaqueElementParent = 39
  case orientation = 40
  /// The parent element. Guest attribute 2184.
  case parent = 41
  case placeholderValue = 42
  case position = 43
  case previousContentSibling = 44
  case role = 45
  case roleDescription = 46
  case selectedTextRange = 47
  case size = 48
  case startsMediaSession = 49
  case stringForRange = 50
  case subrole = 51
  case userTestingSnapshot = 52
  case value = 53
  /// `AXPAttributeRawValue`, renamed so it does not shadow `RawRepresentable.rawValue`.
  case rawValueAttribute = 54
  case minValue = 55
  case maxValue = 56
  case verticalScrollBar = 57
  case visibleOpaqueElements = 58
  // 59 is `AXPUserTestingMarzipanSmuggledValues`, which does not carry the `AXPAttribute` prefix.
  case rawElementData = 60
  case automationType = 61
  // 62 is `AXPImageData`, which does not carry the `AXPAttribute` prefix.
  case debugiOSAttribute = 63
  case valueDescription = 64
  case hostApplicationPid = 65
  case isRemoteElement = 66
  /// Whether the element contains a scrolling descendant. Guest attribute 2172.
  case isScrollAncestor = 67
  case remoteElementIsClientSide = 68
  case remoteElementPid = 69
  case elementForTextInsertionAndDeletion = 70
  case textInputElementRange = 71
  case lineRangeForIndex = 72
  case language = 73
  case nextLineRangeForIndex = 74
  case previousLineRangeForIndex = 75
  case linkedUIElements = 76
  /// The `UIAccessibilityTraits` bitmask. The role is *derived* from this — the translator's role handler branches
  /// on `kAXButtonTrait`, `kAXHeaderTrait`, `kAXTextEntryTrait` and the rest — so this is the un-lossy input to a
  /// classification the role only reports the output of.
  case traits = 77
  /// The traits above, pre-rendered as a string. Guest attribute 2102.
  case traitsAsHumanReadableDescription = 78
  /// The window's accessibility sections, computed live from UIKit's container relationships rather than from the
  /// published tree. Guest attribute 5061, and answered only by application and window elements — everything else
  /// returns nil.
  case windowSections = 79
  /// What kind of container an element is. Guest attribute 2187; the role handler branches on it.
  case containerType = 80
  /// The selected children of a container. Guest attribute 2208.
  case selectedChildren = 81
  /// The element's view controller, as `"<title> [<class name>]"`. Composed by the translator from guest attributes
  /// 5041 and 5042 rather than read from one, so it is special-cased and costs two reads.
  case viewControllerDescription = 82
  case auditIssues = 83
  case notifyVoiceOverAnnouncementCompletionValue = 84
  case firstElementForFocus = 85
  case selectedText = 86
  /// The Voice Control names for the element — often the only human-meaningful handle on an icon-only control.
  /// Special-cased by the translator, which post-processes guest attribute 2186.
  case userInputLabels = 87
  case attributedUserInputLabels = 88
  /// VoiceOver-only supplementary content. Guest attribute 2210.
  case customContent = 89
  /// Guest attributes 2122 and 2121.
  case columnCount = 90
  case rowCount = 91
  case visibleTextRange = 92
  /// The element's path, for shape-bearing elements. Guest attribute 2042.
  case path = 93
  case isReadingContent = 94
  case bookRangeForLineNumber = 95
  case audiograph = 96
  case audiographPlaybackStatus = 97
  case audiographPlaybackProgress = 98
  case supportedGestures = 99
  case elementTextMarkerRange = 100
  case stringForTextMarkerRange = 101
  case textLineEndMarkerForMarker = 102
  case textLineStartMarkerForMarker = 103
  case nextTextMarkerForMarker = 104
  case previousTextMarkerForMarker = 105
  case boundsForTextMarkerRange = 106
  case includeDuringContentReading = 107
  case brailleLabel = 108
  case brailleRoleDescription = 109
  case rangeForTextMarker = 110
  case indexForTextMarker = 111
  /// The point the accessibility server believes a touch reaches; the translator's counterpart to
  /// `XC_kAXXCAttributeVisiblePoint`.
  case visiblePoint = 112
  case elementsForSearchParameters = 113
  case brailleRendererElementFrame = 114
  case brailleCanvasElement2D = 115
  case brailleMap = 116
  case elementForTextMarker = 117
  case attributedValueDescription = 118
  /// Guest attribute 2114.
  case expanded = 119
  /// Guest attribute 2020.
  case url = 120
  case zoomInAtPoint = 121
  case zoomOutAtPoint = 122
  case textInputMarkedRange = 123
  case respondsToInteraction = 124
  case mapFeatureType = 125
  case mapSmartDescriptionData = 126
  case contentSize = 127
  /// A per-element identity, stable for as long as the element lives. No counterpart exists in the
  /// `XC_kAXXCAttribute*` namespace, so it is the only way to tell one element from another across two reads
  /// without comparing every attribute and hoping the combination is unique.
  case memoryAddress = 128
  case applicationOrientation = 129
}

/// The request kinds `-[AXPTranslator processTranslatorRequest:]` dispatches on, decoded from its jump
/// table. Only the ones idb sends are named.
@frozen public enum BridgeAXTranslatorRequestType: Int, Sendable {
  /// One attribute, named by the request's `attributeType`.
  case attribute = 2
  /// Many attributes of one element, carried under `parameters["attributes"]` as an array of
  /// `BridgeAXTranslatorAttribute` raw values, answered as a dictionary keyed by the same numbers. The
  /// handler forwards the batch to `AXUIElementCopyMultipleAttributeValues`, computing the attributes it
  /// has no guest counterpart for in the same pass. Passing an array rather than that dictionary as the
  /// parameters throws inside the guest and takes the reader down with it.
  case multipleAttribute = 5

  /// The `parameters` key a multiple-attribute request carries its attribute list under.
  public static let attributesParameterKey = "attributes"
}
