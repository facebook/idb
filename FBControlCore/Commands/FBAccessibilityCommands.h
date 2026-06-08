/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 Keys for accessibility element dictionaries.
 */
typedef NSString *FBAXKeys NS_STRING_ENUM;

extern FBAXKeys _Nonnull const FBAXKeysLabel;
extern FBAXKeys _Nonnull const FBAXKeysFrame;
extern FBAXKeys _Nonnull const FBAXKeysValue;
extern FBAXKeys _Nonnull const FBAXKeysUniqueID;
extern FBAXKeys _Nonnull const FBAXKeysType;
extern FBAXKeys _Nonnull const FBAXKeysTitle;
extern FBAXKeys _Nonnull const FBAXKeysFrameDict;
extern FBAXKeys _Nonnull const FBAXKeysHelp;
extern FBAXKeys _Nonnull const FBAXKeysEnabled;
extern FBAXKeys _Nonnull const FBAXKeysCustomActions;
extern FBAXKeys _Nonnull const FBAXKeysRole;
extern FBAXKeys _Nonnull const FBAXKeysRoleDescription;
extern FBAXKeys _Nonnull const FBAXKeysSubrole;
extern FBAXKeys _Nonnull const FBAXKeysContentRequired;
extern FBAXKeys _Nonnull const FBAXKeysPID NS_SWIFT_NAME(pid);
extern FBAXKeys _Nonnull const FBAXKeysTraits;
extern FBAXKeys _Nonnull const FBAXKeysExpanded;
extern FBAXKeys _Nonnull const FBAXKeysPlaceholder;
extern FBAXKeys _Nonnull const FBAXKeysHidden;
extern FBAXKeys _Nonnull const FBAXKeysFocused;
extern FBAXKeys _Nonnull const FBAXKeysIsRemote;

/**
 Subset of FBAXKeys whose values are strings, suitable for element search matching.
 */
typedef NSString *FBAXSearchableKey NS_STRING_ENUM;

extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyLabel;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyUniqueID;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyValue;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyTitle;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyRole;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyRoleDescription;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeySubrole;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyHelp;
extern FBAXSearchableKey _Nonnull const FBAXSearchableKeyPlaceholder;

/**
 Default set of keys returned when no specific keys are requested.
 */
extern NSSet<FBAXKeys> *_Nonnull FBAXKeysDefaultSet(void);

/**
 The direction of an accessibility scroll action.
 */
typedef NS_ENUM(NSUInteger, FBAccessibilityScrollDirection) {
  FBAccessibilityScrollDirectionUp,
  FBAccessibilityScrollDirectionDown,
  FBAccessibilityScrollDirectionLeft,
  FBAccessibilityScrollDirectionRight,
  FBAccessibilityScrollDirectionToVisible NS_SWIFT_NAME(visible),
};

// `FBAccessibilityElement`, the `FBAccessibilityOperations`/`FBAccessibilityCommands`
// command protocols, and their async counterparts now live in FBSimulatorControl
// (accessibility is simulator-only and the element's implementation depends on
// AccessibilityPlatformTranslation, which FBControlCore must not). FBControlCore
// keeps only the accessibility value layer above: keys, the scroll-direction enum,
// the request options (FBAccessibilityRequestOptions.swift), and the response
// types (FBAccessibilityResponse.swift).
