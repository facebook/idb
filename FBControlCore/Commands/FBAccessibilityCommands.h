/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Keys for accessibility element dictionaries.
 */
typedef NSString *FBAXKeys NS_STRING_ENUM;

extern FBAXKeys const FBAXKeysLabel;
extern FBAXKeys const FBAXKeysFrame;
extern FBAXKeys const FBAXKeysValue;
extern FBAXKeys const FBAXKeysUniqueID;
extern FBAXKeys const FBAXKeysType;
extern FBAXKeys const FBAXKeysTitle;
extern FBAXKeys const FBAXKeysFrameDict;
extern FBAXKeys const FBAXKeysHelp;
extern FBAXKeys const FBAXKeysEnabled;
extern FBAXKeys const FBAXKeysCustomActions;
extern FBAXKeys const FBAXKeysRole;
extern FBAXKeys const FBAXKeysRoleDescription;
extern FBAXKeys const FBAXKeysSubrole;
extern FBAXKeys const FBAXKeysContentRequired;
extern FBAXKeys const FBAXKeysPID;
extern FBAXKeys const FBAXKeysTraits;
extern FBAXKeys const FBAXKeysExpanded;
extern FBAXKeys const FBAXKeysPlaceholder;
extern FBAXKeys const FBAXKeysHidden;
extern FBAXKeys const FBAXKeysFocused;
extern FBAXKeys const FBAXKeysIsRemote;

/**
 Default set of keys returned when no specific keys are requested.
 */
extern NSSet<FBAXKeys> *FBAXKeysDefaultSet(void);

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
+ (instancetype)defaultOptions;

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
@property (nonatomic, copy, nullable) NSSet<NSString *> *keys;

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
@property (nonatomic, strong, nullable) FBAccessibilityRemoteContentOptions *remoteContentOptions;

/**
 Creates options with default values.
 */
+ (instancetype)defaultOptions;

@end

/**
 Profiling data collected during accessibility operations.
 This provides visibility into the performance characteristics of the AX subsystem.
 */
@interface FBAccessibilityProfilingData : NSObject

/**
 The number of accessibility elements that were serialized.
 */
@property (nonatomic, assign, readonly) int64_t elementCount;

/**
 The number of attribute fetches made on accessibility elements.
 Each property access (accessibilityLabel, accessibilityFrame, etc.) counts as one fetch.
 */
@property (nonatomic, assign, readonly) int64_t attributeFetchCount;

/**
 The number of XPC calls made to the simulator's accessibility service.
 */
@property (nonatomic, assign, readonly) int64_t xpcCallCount;

/**
 The time spent in performWithTranslator (getting the translation object).
 */
@property (nonatomic, assign, readonly) CFAbsoluteTime translationDuration;

/**
 The time spent converting the translation object to a platform element.
 */
@property (nonatomic, assign, readonly) CFAbsoluteTime elementConversionDuration;

/**
 The time spent serializing the accessibility tree.
 */
@property (nonatomic, assign, readonly) CFAbsoluteTime serializationDuration;

/**
 The total time spent in XPC calls.
 */
@property (nonatomic, assign, readonly) CFAbsoluteTime totalXPCDuration;

/**
 The set of keys that were fetched during serialization.
 Useful for tests to verify which attributes were actually accessed.
 */
@property (nonatomic, strong, readonly) NSSet<NSString *> *fetchedKeys;

/**
 Designated initializer.
 */
- (instancetype)initWithElementCount:(int64_t)elementCount
                  attributeFetchCount:(int64_t)attributeFetchCount
                         xpcCallCount:(int64_t)xpcCallCount
                  translationDuration:(CFAbsoluteTime)translationDuration
            elementConversionDuration:(CFAbsoluteTime)elementConversionDuration
               serializationDuration:(CFAbsoluteTime)serializationDuration
                     totalXPCDuration:(CFAbsoluteTime)totalXPCDuration
                          fetchedKeys:(NSSet<NSString *> *)fetchedKeys;

/**
 Returns the profiling data as a JSON-serializable dictionary.
 Times are converted to milliseconds.
 */
- (NSDictionary<NSString *, NSNumber *> *)asDictionary;

@end

/**
 Response object containing accessibility elements and optional profiling data.
 */
@interface FBAccessibilityElementsResponse : NSObject

/**
 The accessibility elements. May be an NSArray (flat/nested) or NSDictionary (single element).
 */
@property (nonatomic, strong, readonly) id elements;

/**
 Profiling data collected during the operation, if profiling was enabled.
 */
@property (nonatomic, strong, readonly, nullable) FBAccessibilityProfilingData *profilingData;

/**
 The proportion of the screen covered by accessibility element frames (0.0 - 1.0).
 Nil if coverage calculation was not requested (collectFrameCoverage = NO).
 Low values (e.g., < 0.1) suggest potential remote content like WebViews.
 */
@property (nonatomic, strong, readonly, nullable) NSNumber *frameCoverage;

/**
 Additional coverage discovered via grid-based hit-testing for remote content.
 This is the coverage added by remote elements not found in the main traversal.
 Nil if remote content discovery was not performed or found no additional elements.
 */
@property (nonatomic, strong, readonly, nullable) NSNumber *additionalFrameCoverage;

/**
 Designated initializer.
 */
- (instancetype)initWithElements:(id)elements
                   profilingData:(nullable FBAccessibilityProfilingData *)profilingData
                   frameCoverage:(nullable NSNumber *)frameCoverage
         additionalFrameCoverage:(nullable NSNumber *)additionalFrameCoverage;

/**
 Returns a JSON-serializable dictionary with elements always embedded.
 Format: {"elements": <elements>, "profile": <profile_dict>, "coverage": <coverage_dict>}
 Profile and coverage keys are included only when the corresponding data is present.
 Use this when you need a single serializable object. Use `elements` when you need raw element data.
 */
- (NSDictionary<NSString *, id> *)asDictionary;

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
- (nullable FBAccessibilityElementsResponse *)serializeWithOptions:(FBAccessibilityRequestOptions *)options
                                                             error:(NSError **)error;

/**
 Perform an accessibility tap (AXPress).

 @param expectedLabel if provided, the label will be verified before tapping.
 @param error an error out parameter.
 @return YES on success, NO on failure.
 */
- (BOOL)tapWithExpectedLabel:(nullable NSString *)expectedLabel error:(NSError **)error;

/**
 Perform an accessibility scroll on the element.

 @param direction the scroll direction.
 @param error an error out parameter.
 @return YES on success, NO on failure.
 */
- (BOOL)scrollWithDirection:(FBAccessibilityScrollDirection)direction error:(NSError **)error;

/**
 Close the element, deregistering the token. Called automatically on dealloc as a safety net.
 After close, serialization will fail. Actions (tap) may still work but are unsupported.
 */
- (void)close;

@end

/**
 Used for internal and external implementation.
 */
@protocol FBAccessibilityOperations <NSObject>

/**
 Obtain an opaque element at the given point.
 The element keeps the translation token registered so that it can be serialized or acted upon.
 The caller must call -close on the returned element when done.

 @param point the coordinate at which to obtain the accessibility element.
 @return a future wrapping the element.
 */
- (FBFuture<FBAccessibilityElement *> *)accessibilityElementAtPoint:(CGPoint)point;

/**
 Obtain an opaque element for the frontmost application.
 The element keeps the translation token registered so that it can be serialized (full tree traversal) or acted upon.
 The caller must call -close on the returned element when done.

 @return a future wrapping the element.
 */
- (FBFuture<FBAccessibilityElement *> *)accessibilityElementForFrontmostApplication;

@end


/**
 Commands relating to Accessibility.
 */
@protocol FBAccessibilityCommands <NSObject, FBiOSTargetCommand, FBAccessibilityOperations>

@end

NS_ASSUME_NONNULL_END
