/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBFuture;
@class FBFutureContext;

@protocol FBControlCoreLogger;

/**
 The Error Domain for FBControlCore.
 */
extern NSString * _Nonnull const FBControlCoreErrorDomain;

/**
 Helpers for constructing Errors representing errors in FBControlCore & adding additional diagnosis.
 */
@interface FBControlCoreError : NSObject

/**
 Describes the build error using the description.
 */
+ (nonnull instancetype)describe:(nonnull NSString *)description;
- (nonnull instancetype)describe:(nonnull NSString *)description;
+ (nonnull instancetype)describeFormat:(nonnull NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (nonnull instancetype)describeFormat:(nonnull NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/*
 Adds the Cause of the Error.
 */
+ (nonnull instancetype)causedBy:(nullable NSError *)cause;
- (nonnull instancetype)causedBy:(nullable NSError *)cause;

/**
 For returning early from failing conditions.
 */
- (BOOL)failBool:(NSError * _Nullable * _Nullable)error;
- (int)failInt:(NSError * _Nullable * _Nullable)error;
- (unsigned int)failUInt:(NSError * _Nullable * _Nullable)error;
- (CGRect)failRect:(NSError * _Nullable * _Nullable)error;
- (nullable void *)failPointer:(NSError * _Nullable * _Nullable)error;
- (nullable id)fail:(NSError * _Nullable * _Nullable)error;
- (nonnull FBFuture *)failFuture;
- (nonnull FBFutureContext *)failFutureContext;

/**
 Attach additional diagnostic information.
 */
- (nonnull instancetype)extraInfo:(nonnull NSString *)key value:(nonnull id)value;

/**
 Prints a recursive description in the error.
 */
- (nonnull instancetype)recursiveDescription;
- (nonnull instancetype)noRecursiveDescription;

/**
 Updates the Error Domain of the receiver.

 @param domain the error domain to update with.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)inDomain:(nonnull NSString *)domain;

/**
 Updates the Error Code of the receiver.

 @param code the Error Code to update with.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)code:(NSInteger)code;

/**
 Builds the Error with the applied arguments.
 */
- (nonnull NSError *)build;

@end

@interface FBControlCoreError (Constructors)

/**
 Construct a simple error with the provided description.
 */
+ (nonnull NSError *)errorForDescription:(nonnull NSString *)description;

/**
 Construct an error from a format string.
 */
+ (nonnull NSError *)errorForFormat:(nonnull NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/**
 Return NO, wrapping `failureCause` in the FBControlCore domain.
 */
+ (BOOL)failBoolWithError:(nonnull NSError *)failureCause errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return NO, wraping wrapping `failureCause` in the FBControlCore domain with an additional description.
 */
+ (BOOL)failBoolWithError:(nonnull NSError *)failureCause description:(nonnull NSString *)description errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return NO with a simple failure message.
 */
+ (BOOL)failBoolWithErrorMessage:(nonnull NSString *)errorMessage errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return nil with a simple failure message.
 */
+ (nullable id)failWithErrorMessage:(nonnull NSString *)errorMessage errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBControlCore domain.
 */
+ (nullable id)failWithError:(nonnull NSError *)failureCause errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBControlCore domain with an additional description.
 */
+ (nullable id)failWithError:(nonnull NSError *)failureCause description:(nonnull NSString *)description errorOut:(NSError * _Nullable * _Nullable)errorOut;

/**
 Return A Future that wraps the error.

 @param error the error to wrap.
 */
+ (nonnull FBFuture *)failFutureWithError:(nonnull NSError *)error;

@end
