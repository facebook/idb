/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

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
extern FBAXKeys _Nonnull const FBAXKeysPID;
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
 Options for fetching remote process elements (e.g., WebView content).
 Remote elements are in separate processes and require grid-based hit-testing to discover.
 */
@interface FBAccessibilityRemoteContentOptions : NSObject <NSCopying>

/**
 Grid step size in points for sampling. Smaller = more thorough but slower.
 Default: 50.0
 */
@property (nonatomic, assign) CGFloat gridStepSize;

/**
 Region to sample. CGRectNull = full screen (default).
 */
@property (nonatomic, assign) CGRect region;

/**
 Maximum points to sample. 0 = unlimited (default).
 */
@property (nonatomic, assign) NSUInteger maxPoints;

/**
 Creates options with default values.
 */
+ (nonnull instancetype)defaultOptions;

@end

/**
 Request options for accessibility operations.
 Consolidates all parameters needed for an accessibility query.
 */
@interface FBAccessibilityRequestOptions : NSObject <NSCopying>

/**
 If YES, data is returned in nested format with children. If NO, flat format.
 Default: NO
 */
@property (nonatomic, assign) BOOL nestedFormat;

/**
 Set of string keys to filter which properties are returned.
 Default: FBAXKeysDefaultSet() (all standard keys).
 Set to nil to use all default keys.
 */
@property (nullable, nonatomic, copy) NSSet<NSString *> *keys;

/**
 Log accessibility requests and responses to the simulator's logger.
 Default: NO
 */
@property (nonatomic, assign) BOOL enableLogging;

/**
 Collect profiling data (element counts, timing metrics).
 Default: NO
 */
@property (nonatomic, assign) BOOL enableProfiling;

/**
 Enable frame coverage calculation during traversal.
 When YES, frameCoverage will be populated in the response.
 Default: NO
 */
@property (nonatomic, assign) BOOL collectFrameCoverage;

/**
 Options for remote content fetching. If nil (default), remote content is not fetched.
 Remote elements are in separate processes (e.g., WebKit content in Safari) and require
 grid-based hit-testing to discover, which adds ~270ms overhead.
 */
@property (nullable, nonatomic, strong) FBAccessibilityRemoteContentOptions *remoteContentOptions;

/**
 Creates options with default values.
 */
+ (nonnull instancetype)defaultOptions;

@end

/**
 Profiling data collected during accessibility operations.
 This provides visibility into the performance characteristics of the AX subsystem.
 */
@interface FBAccessibilityProfilingData : NSObject

/**
 The number of accessibility elements that were serialized.
 */
@property (nonatomic, readonly, assign) int64_t elementCount;

/**
 The number of attribute fetches made on accessibility elements.
 Each property access (accessibilityLabel, accessibilityFrame, etc.) counts as one fetch.
 */
@property (nonatomic, readonly, assign) int64_t attributeFetchCount;

/**
 The number of XPC calls made to the simulator's accessibility service.
 */
@property (nonatomic, readonly, assign) int64_t xpcCallCount;

/**
 The time spent in performWithTranslator (getting the translation object).
 */
@property (nonatomic, readonly, assign) CFAbsoluteTime translationDuration;

/**
 The time spent converting the translation object to a platform element.
 */
@property (nonatomic, readonly, assign) CFAbsoluteTime elementConversionDuration;

/**
 The time spent serializing the accessibility tree.
 */
@property (nonatomic, readonly, assign) CFAbsoluteTime serializationDuration;

/**
 The total time spent in XPC calls.
 */
@property (nonatomic, readonly, assign) CFAbsoluteTime totalXPCDuration;

/**
 The set of keys that were fetched during serialization.
 Useful for tests to verify which attributes were actually accessed.
 */
@property (nonnull, nonatomic, readonly, strong) NSSet<NSString *> *fetchedKeys;

/**
 Designated initializer.
 */
- (nonnull instancetype)initWithElementCount:(int64_t)elementCount
                         attributeFetchCount:(int64_t)attributeFetchCount
                                xpcCallCount:(int64_t)xpcCallCount
                         translationDuration:(CFAbsoluteTime)translationDuration
                   elementConversionDuration:(CFAbsoluteTime)elementConversionDuration
                       serializationDuration:(CFAbsoluteTime)serializationDuration
                            totalXPCDuration:(CFAbsoluteTime)totalXPCDuration
                                 fetchedKeys:(nonnull NSSet<NSString *> *)fetchedKeys;

/**
 Returns the profiling data as a JSON-serializable dictionary.
 Times are converted to milliseconds.
 */
- (nonnull NSDictionary<NSString *, NSNumber *> *)asDictionary;

@end

/**
 Response object containing accessibility elements and optional profiling data.
 */
@interface FBAccessibilityElementsResponse : NSObject

/**
 The accessibility elements. May be an NSArray (flat/nested) or NSDictionary (single element).
 */
@property (nonnull, nonatomic, readonly, strong) id elements;

/**
 Profiling data collected during the operation, if profiling was enabled.
 */
@property (nullable, nonatomic, readonly, strong) FBAccessibilityProfilingData *profilingData;

/**
 The proportion of the screen covered by accessibility element frames (0.0 - 1.0).
 Nil if coverage calculation was not requested (collectFrameCoverage = NO).
 Low values (e.g., < 0.1) suggest potential remote content like WebViews.
 */
@property (nullable, nonatomic, readonly, strong) NSNumber *frameCoverage;

/**
 Additional coverage discovered via grid-based hit-testing for remote content.
 This is the coverage added by remote elements not found in the main traversal.
 Nil if remote content discovery was not performed or found no additional elements.
 */
@property (nullable, nonatomic, readonly, strong) NSNumber *additionalFrameCoverage;

/**
 Designated initializer.
 */
- (nonnull instancetype)initWithElements:(nonnull id)elements
                           profilingData:(nullable FBAccessibilityProfilingData *)profilingData
                           frameCoverage:(nullable NSNumber *)frameCoverage
                 additionalFrameCoverage:(nullable NSNumber *)additionalFrameCoverage;

/**
 Returns a JSON-serializable dictionary with elements always embedded.
 Format: {"elements": <elements>, "profile": <profile_dict>, "coverage": <coverage_dict>}
 Profile and coverage keys are included only when the corresponding data is present.
 Use this when you need a single serializable object. Use `elements` when you need raw element data.
 */
- (nonnull NSDictionary<NSString *, id> *)asDictionary;

@end

/**
 The direction of an accessibility scroll action.
 */
typedef NS_ENUM(NSUInteger, FBAccessibilityScrollDirection) {
  FBAccessibilityScrollDirectionUp,
  FBAccessibilityScrollDirectionDown,
  FBAccessibilityScrollDirectionLeft,
  FBAccessibilityScrollDirectionRight,
  FBAccessibilityScrollDirectionToVisible,
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
