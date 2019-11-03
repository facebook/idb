/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAccessibilityTraits.h"

#import <AXRuntime/AXTraits.h>

inline BOOL AXBitmaskContainsAllTraits(uint64_t bitmask, uint64_t traits)
{
  return (bitmask & traits) == traits;
}

inline BOOL AXBitmaskContainsAnyOfTraits(uint64_t bitmask, uint64_t traits)
{
  return (bitmask & traits) != 0;
}

NSSet<NSString *> *AXExtractTraits(uint64_t traitBitmask)
{
  if (!traitBitmask) {
    return [NSSet setWithObject:@"None"];
  }
  __block uint64_t bitmask = traitBitmask;
  NSMutableSet<NSString *> *extractedTraits = [NSMutableSet set];
  [AXTraitToNameMap() enumerateKeysAndObjectsUsingBlock:^(NSNumber *traitNumber, NSString *name, BOOL *stop) {
    uint64_t trait = traitNumber.unsignedLongLongValue;
    if (AXBitmaskContainsAllTraits(bitmask, trait)) {
      bitmask -= trait;
      [extractedTraits addObject:name];
    }
  }];
  if (bitmask) {
    [extractedTraits addObject:@"Unknown"];
  }
  return extractedTraits;
}

NSString *AXExtractTypeFromTraits(uint64_t traits)
{
  if (AXBitmaskContainsAnyOfTraits(traits, AXTraitButton | AXTraitLaunchIcon | AXTraitKeyboardKey | AXTraitBackButton | AXTraitTabButton | AXTraitDeleteKey | AXTraitPopupButton | AXTraitToggle)) {
    return @"Button";
  }
  if (AXBitmaskContainsAnyOfTraits(traits, AXTraitTextOperationsAvailable | AXTraitTextEntry | AXTraitSearchField | AXTraitSecureTextField)) {
    return @"TextEntry";
  }
  if (AXBitmaskContainsAnyOfTraits(traits, AXTraitStaticText)) {
    return @"Text";
  }
  return @"Unknown";
}

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
