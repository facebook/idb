/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The attribute vocabulary `AXPTranslator` answers in — a separate namespace from XCTest's
 * `XC_kAXXCAttribute*` names, with separate server-side handlers; an element handle from one is not
 * accepted by the other.
 *
 * Values are the enum's own indices, recovered from `__AXPAttributeToString` in the guest
 * `AccessibilityPlatformTranslation` binary (0–129 is the bound both it and
 * `-[AXPTranslator_iOS attributeFromRequest:]` enforce); identical on the 26.4, 26.5 and 27.0 runtimes.
 *
 * **Declared is not fetchable.** Only the name each index binds to is verified. The translator raises on
 * a value it cannot convert, and an uncaught raise takes the reader down, so anything added to a fetch
 * list needs a run against a real screen first.
 */
typedef NS_ENUM(NSInteger, FBAXPAttribute) {
  /** The sentinel the table starts at, and what the translator answers for an index it does not know. */
  FBAXPAttributeUndefined = 0,
  FBAXPAttributeActivationPoint = 1,
  FBAXPAttributeAssistiveTechnologyFocused = 2,
  FBAXPAttributeAttributedLabel = 3,
  FBAXPAttributeAttributedStringForRange = 4,
  FBAXPAttributeBoundsForRange = 5,
  FBAXPAttributeBundleIdentifier = 6,
  FBAXPAttributeClassName = 7,
  FBAXPAttributeChildren = 8,
  FBAXPAttributeChildrenInNavigationOrder = 9,
  FBAXPAttributeChildrenContainerGroupingBehaviorHasOverridingParentDelegate = 10,
  FBAXPAttributeParentDiscardsChildrenContainerGroupingBehavior = 11,
  FBAXPAttributeContextId = 12,
  FBAXPAttributeCustomActions = 13,
  FBAXPAttributeCustomRotors = 14,
  FBAXPAttributeCustomRotorData = 15,
  FBAXPAttributeCustomRotorSearchResult = 16,
  FBAXPAttributeEquivalenceTag = 17,
  FBAXPAttributeFirstContainedElement = 18,
  FBAXPAttributeFocusedElement = 19,
  FBAXPAttributeFocusedOpaqueElement = 20,
  FBAXPAttributeFrame = 21,
  /** Heading depth. Guest attribute 2180. */
  FBAXPAttributeHeadingLevel = 22,
  FBAXPAttributeHelp = 23,
  FBAXPAttributeHorizontalScrollBar = 24,
  FBAXPAttributeIdentifier = 25,
  /** Whether the element is an accessibility element in its own right rather than a container. Guest
      attribute 2016; the translator's role handler branches on it to choose `Group` over
      `GenericElement`. */
  FBAXPAttributeIsElement = 26,
  /** No counterpart in the `XC_kAXXCAttribute*` namespace. */
  FBAXPAttributeIsEnabled = 27,
  FBAXPAttributeIsFocused = 28,
  FBAXPAttributeIsOpaqueElementProvider = 29,
  FBAXPAttributeIsSelected = 30,
  /** Whether the element is still live. Guest attribute 2056. */
  FBAXPAttributeIsValid = 31,
  FBAXPAttributeIsVisible = 32,
  FBAXPAttributeLabel = 33,
  FBAXPAttributeLastContainedElement = 34,
  FBAXPAttributeMoveFocusToNextOpaqueElement = 35,
  FBAXPAttributeMoveFocusToPreviousOpaqueElement = 36,
  FBAXPAttributeNextContentSibling = 37,
  FBAXPAttributeNumberOfCharacters = 38,
  FBAXPAttributeOpaqueElementParent = 39,
  FBAXPAttributeOrientation = 40,
  /** The parent element. Guest attribute 2184. */
  FBAXPAttributeParent = 41,
  FBAXPAttributePlaceholderValue = 42,
  FBAXPAttributePosition = 43,
  FBAXPAttributePreviousContentSibling = 44,
  FBAXPAttributeRole = 45,
  FBAXPAttributeRoleDescription = 46,
  FBAXPAttributeSelectedTextRange = 47,
  FBAXPAttributeSize = 48,
  FBAXPAttributeStartsMediaSession = 49,
  FBAXPAttributeStringForRange = 50,
  FBAXPAttributeSubrole = 51,
  FBAXPAttributeUserTestingSnapshot = 52,
  FBAXPAttributeValue = 53,
  FBAXPAttributeRawValue = 54,
  FBAXPAttributeMinValue = 55,
  FBAXPAttributeMaxValue = 56,
  FBAXPAttributeVerticalScrollBar = 57,
  FBAXPAttributeVisibleOpaqueElements = 58,
  // 59 is `AXPUserTestingMarzipanSmuggledValues`, which does not carry the `AXPAttribute` prefix.
  FBAXPAttributeRawElementData = 60,
  FBAXPAttributeAutomationType = 61,
  // 62 is `AXPImageData`, which does not carry the `AXPAttribute` prefix.
  FBAXPAttributeDebugiOSAttribute = 63,
  FBAXPAttributeValueDescription = 64,
  FBAXPAttributeHostApplicationPid = 65,
  FBAXPAttributeIsRemoteElement = 66,
  /** Whether the element contains a scrolling descendant. Guest attribute 2172. */
  FBAXPAttributeIsScrollAncestor = 67,
  FBAXPAttributeRemoteElementIsClientSide = 68,
  FBAXPAttributeRemoteElementPid = 69,
  FBAXPAttributeElementForTextInsertionAndDeletion = 70,
  FBAXPAttributeTextInputElementRange = 71,
  FBAXPAttributeLineRangeForIndex = 72,
  FBAXPAttributeLanguage = 73,
  FBAXPAttributeNextLineRangeForIndex = 74,
  FBAXPAttributePreviousLineRangeForIndex = 75,
  FBAXPAttributeLinkedUIElements = 76,
  /** The `UIAccessibilityTraits` bitmask. The role is *derived* from this — the translator's role handler
      branches on `kAXButtonTrait`, `kAXHeaderTrait`, `kAXTextEntryTrait` and the rest — so this is the
      un-lossy input to a classification the role only reports the output of. */
  FBAXPAttributeTraits = 77,
  /** The traits above, pre-rendered as a string. Guest attribute 2102. */
  FBAXPAttributeTraitsAsHumanReadableDescription = 78,
  /** The window's accessibility sections, computed live from UIKit's container relationships rather than
      from the published tree. Guest attribute 5061, and answered only by application and window
      elements — everything else returns nil. */
  FBAXPAttributeWindowSections = 79,
  /** What kind of container an element is. Guest attribute 2187; the role handler branches on it. */
  FBAXPAttributeContainerType = 80,
  /** The selected children of a container. Guest attribute 2208. */
  FBAXPAttributeSelectedChildren = 81,
  /** The element's view controller, as `"<title> [<class name>]"`. Composed by the translator from guest
      attributes 5041 and 5042 rather than read from one, so it is special-cased and costs two reads. */
  FBAXPAttributeViewControllerDescription = 82,
  FBAXPAttributeAuditIssues = 83,
  FBAXPAttributeNotifyVoiceOverAnnouncementCompletionValue = 84,
  FBAXPAttributeFirstElementForFocus = 85,
  FBAXPAttributeSelectedText = 86,
  /** The Voice Control names for the element — often the only human-meaningful handle on an icon-only
      control. Special-cased by the translator, which post-processes guest attribute 2186. */
  FBAXPAttributeUserInputLabels = 87,
  FBAXPAttributeAttributedUserInputLabels = 88,
  /** VoiceOver-only supplementary content. Guest attribute 2210. */
  FBAXPAttributeCustomContent = 89,
  /** Guest attributes 2122 and 2121. */
  FBAXPAttributeColumnCount = 90,
  FBAXPAttributeRowCount = 91,
  FBAXPAttributeVisibleTextRange = 92,
  /** The element's path, for shape-bearing elements. Guest attribute 2042. */
  FBAXPAttributePath = 93,
  FBAXPAttributeIsReadingContent = 94,
  FBAXPAttributeBookRangeForLineNumber = 95,
  FBAXPAttributeAudiograph = 96,
  FBAXPAttributeAudiographPlaybackStatus = 97,
  FBAXPAttributeAudiographPlaybackProgress = 98,
  FBAXPAttributeSupportedGestures = 99,
  FBAXPAttributeElementTextMarkerRange = 100,
  FBAXPAttributeStringForTextMarkerRange = 101,
  FBAXPAttributeTextLineEndMarkerForMarker = 102,
  FBAXPAttributeTextLineStartMarkerForMarker = 103,
  FBAXPAttributeNextTextMarkerForMarker = 104,
  FBAXPAttributePreviousTextMarkerForMarker = 105,
  FBAXPAttributeBoundsForTextMarkerRange = 106,
  FBAXPAttributeIncludeDuringContentReading = 107,
  FBAXPAttributeBrailleLabel = 108,
  FBAXPAttributeBrailleRoleDescription = 109,
  FBAXPAttributeRangeForTextMarker = 110,
  FBAXPAttributeIndexForTextMarker = 111,
  /** The point the accessibility server believes a touch reaches; the translator's counterpart to
      `XC_kAXXCAttributeVisiblePoint`. */
  FBAXPAttributeVisiblePoint = 112,
  FBAXPAttributeElementsForSearchParameters = 113,
  FBAXPAttributeBrailleRendererElementFrame = 114,
  FBAXPAttribute2DBrailleCanvasElement = 115,
  FBAXPAttributeBrailleMap = 116,
  FBAXPAttributeElementForTextMarker = 117,
  FBAXPAttributeAttributedValueDescription = 118,
  /** Guest attribute 2114. */
  FBAXPAttributeExpanded = 119,
  /** Guest attribute 2020. */
  FBAXPAttributeURL = 120,
  FBAXPAttributeZoomInAtPoint = 121,
  FBAXPAttributeZoomOutAtPoint = 122,
  FBAXPAttributeTextInputMarkedRange = 123,
  FBAXPAttributeRespondsToInteraction = 124,
  FBAXPAttributeMapFeatureType = 125,
  FBAXPAttributeMapSmartDescriptionData = 126,
  FBAXPAttributeContentSize = 127,
  /** A per-element identity, stable for as long as the element lives. No counterpart exists in the
      `XC_kAXXCAttribute*` namespace, so it is the only way to tell one element from another across two
      reads without comparing every attribute and hoping the combination is unique. */
  FBAXPAttributeMemoryAddress = 128,
  FBAXPAttributeApplicationOrientation = 129,
};

/**
 * The request kinds `-[AXPTranslator processTranslatorRequest:]` dispatches on, decoded from its jump
 * table. Only the two a reader needs are named.
 */
typedef NS_ENUM(NSInteger, FBAXPRequestType) {
  FBAXPRequestTypeAttribute = 2,
  /** Carries its attribute list under `parameters[@"attributes"]`; the handler forwards the batch to
      `AXUIElementCopyMultipleAttributeValues`. Passing an array rather than that dictionary throws
      inside the guest and takes the reader down with it. */
  FBAXPRequestTypeMultipleAttribute = 5,
};

NS_ASSUME_NONNULL_END
