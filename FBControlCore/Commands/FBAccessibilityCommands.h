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

// `FBAccessibilityRemoteContentOptions` and `FBAccessibilityRequestOptions` are
// now defined in Swift (see FBAccessibilityRequestOptions.swift). `RequestOptions`
// is forward-declared here for the ObjC `FBAccessibilityElement` interface below.
// ObjC code that reads them imports <FBControlCore/FBControlCore-Swift.h>.
@class FBAccessibilityRequestOptions;

// `FBAccessibilityProfilingData` and `FBAccessibilityElementsResponse` are now
// defined in Swift (see FBAccessibilityResponse.swift). They are forward-declared
// here so the ObjC `FBAccessibilityElement` interface below can reference the
// response type. ObjC code that constructs them imports <FBControlCore/FBControlCore-Swift.h>.
@class FBAccessibilityElementsResponse;

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

/**
 An opaque accessibility element with a managed token lifecycle.
 The element's translation token remains registered as long as the element is open,
 allowing serialization (attribute reads go through XPC callbacks routed by token).
 Actions (tap, scroll) are direct calls on the element and do not require the token.
 Call -close when done to deregister the token. After close, serialization will fail.
 */
@interface FBAccessibilityElement : NSObject

/**
 Serialize the element to a full response (preserves profiling/coverage data).

 @param options the request options controlling format, keys, and profiling.
 @param error an error out parameter.
 @return the serialized response, or nil on failure.
 */
- (nullable FBAccessibilityElementsResponse *)serializeWithOptions:(nonnull FBAccessibilityRequestOptions *)options
                                                             error:(NSError * _Nullable * _Nullable)error;

/**
 Perform an unconditional accessibility tap (AXPress) without any label verification.

 @param error an error out parameter.
 @return YES on success, NO on failure.
 */
- (BOOL)tapWithError:(NSError * _Nullable * _Nullable)error;

/**
 Read the string value of a searchable accessibility key from this element.

 @param key the searchable key to read.
 @param error an error out parameter.
 @return the string value, or nil if the key has no string value or on failure.
 */
- (nullable NSString *)stringValueForSearchableKey:(nonnull FBAXSearchableKey)key error:(NSError * _Nullable * _Nullable)error;

/**
 Perform an accessibility scroll on the element.

 @param direction the scroll direction.
 @param error an error out parameter.
 @return YES on success, NO on failure.
 */
- (BOOL)scrollWithDirection:(FBAccessibilityScrollDirection)direction error:(NSError * _Nullable * _Nullable)error;

/**
 Set the accessibility value of the element (e.g., text field content, slider position).

 @param value the value to set.
 @param error an error out parameter.
 @return YES on success, NO on failure.
 */
- (BOOL)setValue:(nonnull id)value error:(NSError * _Nullable * _Nullable)error;

/**
 Close the element, deregistering the token. Called automatically on dealloc as a safety net.
 After close, serialization will fail. Actions (tap) may still work but are unsupported.
 */
- (void)close;

@end

@protocol FBAccessibilityCommands;
@protocol FBAccessibilityOperations;
