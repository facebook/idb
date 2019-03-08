/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/*
 Values were extracted from _kAXButtonTrait like statics in
   .../Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/
   CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/
   System/Library/PrivateFrameworks/AXRuntime.framework
 */
#define FBBIT64(b) ((uint64_t)1 << b)
typedef NS_OPTIONS(uint64_t, AXTraits) {
  AXTraitNone = 0,
  AXTraitButton = FBBIT64(0),
  AXTraitLink = FBBIT64(1),
  AXTraitImage = FBBIT64(2),
  AXTraitSelected = FBBIT64(3),
  AXTraitPlaysSound = FBBIT64(4),
  AXTraitKeyboardKey = FBBIT64(5),
  AXTraitStaticText = FBBIT64(6),
  AXTraitSummaryElement = FBBIT64(7),
  AXTraitNotEnabled = FBBIT64(8),
  AXTraitUpdatesFrequently = FBBIT64(9),
  AXTraitSearchField = FBBIT64(10),
  AXTraitStartsMediaSession = FBBIT64(11),
  AXTraitAdjustable = FBBIT64(12),
  AXTraitAllowsDirectInteraction = FBBIT64(13),
  AXTraitCausesPageTurn = FBBIT64(14),
  AXTraitTabBar = FBBIT64(15),
  AXTraitHeader = FBBIT64(16),
  AXTraitWebContent = FBBIT64(17),
  AXTraitTextEntry = FBBIT64(18),
  AXTraitPickerElement = FBBIT64(19),
  AXTraitRadioButton = FBBIT64(20),
  AXTraitIsEditing = FBBIT64(21),
  AXTraitLaunchIcon = FBBIT64(22),
  AXTraitStatusBarElement = FBBIT64(23),
  AXTraitSecureTextField = FBBIT64(24),
  AXTraitInactive = FBBIT64(25),
  AXTraitFooter = FBBIT64(26),
  AXTraitBackButton = FBBIT64(27),
  AXTraitTabButton = FBBIT64(28),
  AXTraitAutoCorrectCandidate = FBBIT64(29),
  AXTraitDeleteKey = FBBIT64(30),
  AXTraitSelectionDismissesItem = FBBIT64(31),
  AXTraitVisited = FBBIT64(32),
  AXTraitScrollable = FBBIT64(33),
  AXTraitSpacer = FBBIT64(34),
  AXTraitTableIndex = FBBIT64(35),
  AXTraitMap = FBBIT64(36),
  AXTraitTextOperationsAvailable = FBBIT64(37),
  AXTraitDraggable = FBBIT64(38),
  AXTraitGesturePracticeRegion = FBBIT64(39),
  AXTraitPopupButton = FBBIT64(40),
  AXTraitAllowsNativeSliding = FBBIT64(41),
  AXTraitMathEquation = FBBIT64(42),
  AXTraitContainedByTable = FBBIT64(43),
  AXTraitContainedByList = FBBIT64(44),
  AXTraitTouchContainer = FBBIT64(45),
  AXTraitSupportsZoom = FBBIT64(46),
  AXTraitTextArea = FBBIT64(47),
  AXTraitBookContent = FBBIT64(48),
  AXTraitContainedByLandmark = FBBIT64(49),
  AXTraitFolderIcon = FBBIT64(50),
  AXTraitReadOnly = FBBIT64(51),
  AXTraitMenuItem = FBBIT64(52),
  AXTraitToggle = FBBIT64(53),
  AXTraitIgnoreItemChooser = FBBIT64(54),
  AXTraitSupportsTrackingDetail = FBBIT64(55),
  AXTraitAlert = FBBIT64(56),
  AXTraitContainedByFieldset = FBBIT64(57),
  AXTraitAllowsLayoutChangeInStatusBar = FBBIT64(58),
};
