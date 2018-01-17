/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "AXTraits.h"

#define FBTraitMapEntry(T) @(T): [@#T substringFromIndex:@"AXTrait".length]
NSDictionary<NSNumber *, NSString *> *AXTraitToNameMap(void)
{
  static NSDictionary<NSNumber *, NSString *> *_mapping;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _mapping = @{
      FBTraitMapEntry(AXTraitButton),
      FBTraitMapEntry(AXTraitLink),
      FBTraitMapEntry(AXTraitImage),
      FBTraitMapEntry(AXTraitSelected),
      FBTraitMapEntry(AXTraitPlaysSound),
      FBTraitMapEntry(AXTraitKeyboardKey),
      FBTraitMapEntry(AXTraitStaticText),
      FBTraitMapEntry(AXTraitSummaryElement),
      FBTraitMapEntry(AXTraitNotEnabled),
      FBTraitMapEntry(AXTraitUpdatesFrequently),
      FBTraitMapEntry(AXTraitSearchField),
      FBTraitMapEntry(AXTraitStartsMediaSession),
      FBTraitMapEntry(AXTraitAdjustable),
      FBTraitMapEntry(AXTraitAllowsDirectInteraction),
      FBTraitMapEntry(AXTraitCausesPageTurn),
      FBTraitMapEntry(AXTraitTabBar),
      FBTraitMapEntry(AXTraitHeader),
      FBTraitMapEntry(AXTraitWebContent),
      FBTraitMapEntry(AXTraitTextEntry),
      FBTraitMapEntry(AXTraitPickerElement),
      FBTraitMapEntry(AXTraitRadioButton),
      FBTraitMapEntry(AXTraitIsEditing),
      FBTraitMapEntry(AXTraitLaunchIcon),
      FBTraitMapEntry(AXTraitStatusBarElement),
      FBTraitMapEntry(AXTraitSecureTextField),
      FBTraitMapEntry(AXTraitInactive),
      FBTraitMapEntry(AXTraitFooter),
      FBTraitMapEntry(AXTraitBackButton),
      FBTraitMapEntry(AXTraitTabButton),
      FBTraitMapEntry(AXTraitAutoCorrectCandidate),
      FBTraitMapEntry(AXTraitDeleteKey),
      FBTraitMapEntry(AXTraitSelectionDismissesItem),
      FBTraitMapEntry(AXTraitVisited),
      FBTraitMapEntry(AXTraitScrollable),
      FBTraitMapEntry(AXTraitSpacer),
      FBTraitMapEntry(AXTraitTableIndex),
      FBTraitMapEntry(AXTraitMap),
      FBTraitMapEntry(AXTraitTextOperationsAvailable),
      FBTraitMapEntry(AXTraitDraggable),
      FBTraitMapEntry(AXTraitGesturePracticeRegion),
      FBTraitMapEntry(AXTraitPopupButton),
      FBTraitMapEntry(AXTraitAllowsNativeSliding),
      FBTraitMapEntry(AXTraitMathEquation),
      FBTraitMapEntry(AXTraitContainedByTable),
      FBTraitMapEntry(AXTraitContainedByList),
      FBTraitMapEntry(AXTraitTouchContainer),
      FBTraitMapEntry(AXTraitSupportsZoom),
      FBTraitMapEntry(AXTraitTextArea),
      FBTraitMapEntry(AXTraitBookContent),
      FBTraitMapEntry(AXTraitContainedByLandmark),
      FBTraitMapEntry(AXTraitFolderIcon),
      FBTraitMapEntry(AXTraitReadOnly),
      FBTraitMapEntry(AXTraitMenuItem),
      FBTraitMapEntry(AXTraitToggle),
      FBTraitMapEntry(AXTraitIgnoreItemChooser),
      FBTraitMapEntry(AXTraitSupportsTrackingDetail),
      FBTraitMapEntry(AXTraitAlert),
      FBTraitMapEntry(AXTraitContainedByFieldset),
      FBTraitMapEntry(AXTraitAllowsLayoutChangeInStatusBar)
    };
  });
  return _mapping;
}
