/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBFuture;
@class FBFutureContext;

@protocol FBControlCoreLogger;

/**
 The Error Domain for FBControlCore.
 */
extern NSString *const FBControlCoreErrorDomain;

/**
 Helpers for constructing Errors representing errors in FBControlCore & adding additional diagnosis.
 */
@interface FBControlCoreError : NSObject

/**
 Describes the build error using the description.
 */
+ (instancetype)describe:(NSString *)description;
- (instancetype)describe:(NSString *)description;
+ (instancetype)describeFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (instancetype)describeFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/*
 Adds the Cause of the Error.
 */
+ (instancetype)causedBy:(nullable NSError *)cause;
- (instancetype)causedBy:(nullable NSError *)cause;

/**
 For returning early from failing conditions.
 */
- (BOOL)failBool:(NSError **)error;
- (int)failInt:(NSError **)error;
- (unsigned int)failUInt:(NSError **)error;
- (CGRect)failRect:(NSError **)error;
- (nullable void *)failPointer:(NSError **)error;
- (nullable id)fail:(NSError **)error;
- (FBFuture *)failFuture;
- (FBFutureContext *)failFutureContext;

/**
 Attach additional diagnostic information.
 */
- (instancetype)extraInfo:(NSString *)key value:(id)value;

/**
 Prints a recursive description in the error.
 */
- (instancetype)recursiveDescription;
- (instancetype)noRecursiveDescription;

/**
 Updates the Error Domain of the receiver.

 @param domain the error domain to update with.
 @return the receiver, for chaining.
 */
- (instancetype)inDomain:(NSString *)domain;

/**
 Updates the Error Code of the receiver.

 @param code the Error Code to update with.
 @return the receiver, for chaining.
 */
- (instancetype)code:(NSInteger)code;

/**
 Builds the Error with the applied arguments.
 */
- (NSError *)build;

@end

@interface FBControlCoreError (Constructors)

/**
 Construct a simple error with the provided description.
 */
+ (NSError *)errorForDescription:(NSString *)description;

/**
 Construct an error from a format string.
 */
+ (NSError *)errorForFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Return NO, wrapping `failureCause` in the FBControlCore domain.
 */
+ (BOOL)failBoolWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;

/**
 Return NO, wraping wrapping `failureCause` in the FBControlCore domain with an additional description.
 */
+ (BOOL)failBoolWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;

/**
 Return NO with a simple failure message.
 */
+ (BOOL)failBoolWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;

/**
 Return nil with a simple failure message.
 */
+ (nullable id)failWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBControlCore domain.
 */
+ (nullable id)failWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBControlCore domain with an additional description.
 */
+ (nullable id)failWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;

/**
 Return A Future that wraps the error.
 
 @param error the error to wrap.
 */
+ (FBFuture *)failFutureWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
