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
 Options for accessibility operations.
 */
typedef NS_OPTIONS(NSUInteger, FBAccessibilityOptions) {
  /** No logging or profiling. */
  FBAccessibilityOptionsNone = 0,
  /** Log accessibility requests and responses to the simulator's logger. */
  FBAccessibilityOptionsLog = 1 << 0,
  /** Collect profiling data (element counts, timing metrics). */
  FBAccessibilityOptionsProfile = 1 << 1,
};

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
 Designated initializer.
 */
- (instancetype)initWithElementCount:(int64_t)elementCount
                  attributeFetchCount:(int64_t)attributeFetchCount
                         xpcCallCount:(int64_t)xpcCallCount
                  translationDuration:(CFAbsoluteTime)translationDuration
            elementConversionDuration:(CFAbsoluteTime)elementConversionDuration
               serializationDuration:(CFAbsoluteTime)serializationDuration
                     totalXPCDuration:(CFAbsoluteTime)totalXPCDuration;

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
 Designated initializer.
 */
- (instancetype)initWithElements:(id)elements profilingData:(nullable FBAccessibilityProfilingData *)profilingData;

@end

/**
 Used for internal and external implementation.
 */
@protocol FBAccessibilityOperations <NSObject>

/**
 The Acessibility Elements.
 Obtain the acessibility elements for the main screen.
 The returned value is fully JSON serializable.

 @param nestedFormat if YES then data is returned in the nested format, NO for flat format
 @param keys optional set of string keys to filter which properties are returned. If nil, all properties are returned.
 @param options bitmask controlling logging and profiling behavior.
 @return FBAccessibilityElementsResponse containing the elements and optional profiling data.
 */
- (FBFuture<FBAccessibilityElementsResponse *> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat keys:(nullable NSSet<NSString *> *)keys options:(FBAccessibilityOptions)options;

/**
 Obtain the acessibility element for the main screen at the given point.
 The returned value is fully JSON serializable.

 @param point the coordinate at which to obtain the accessibility element.
 @param nestedFormat if YES then data is returned in the nested format, NO for flat format
 @param keys optional set of string keys to filter which properties are returned. If nil, all properties are returned.
 @param options bitmask controlling logging and profiling behavior.
 @return FBAccessibilityElementsResponse containing the element and optional profiling data.
 */
- (FBFuture<FBAccessibilityElementsResponse *> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat keys:(nullable NSSet<NSString *> *)keys options:(FBAccessibilityOptions)options;

@end


/**
 Commands relating to Accessibility.
 */
@protocol FBAccessibilityCommands <NSObject, FBiOSTargetCommand, FBAccessibilityOperations>

@end

NS_ASSUME_NONNULL_END
