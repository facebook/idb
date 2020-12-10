/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBEventReporter.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;
@protocol FBEventReporter;
@protocol FBiOSTarget;
@protocol FBiOSTargetFutureDelegate;
@protocol FBiOSTargetOperation;

/**
 An extensible string enum representing an Action Type.
 */
typedef NSString *FBiOSTargetFutureType NS_EXTENSIBLE_STRING_ENUM;

/**
 The Action Type for an Application Launch.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeApplicationLaunch;

/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeAgentLaunch;

/**
 The Action Type for a Test Launch.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeTestLaunch;

/**
 The Action Type for Log Tails.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeLogTail;

/**
 A protocol that represents an operation of indeterminate length.
 */
@protocol FBiOSTargetOperation <NSObject>

/**
 A Optional Future that resolves when the operation has completed.
 For any FBiOSTargetOperation that performs ongoing work, this will be non-nil.
 For any FBiOSTargetOperation that has finished it's work when resolved, this will be nil.
 */
@property (nonatomic, strong, nullable, readonly) FBFuture<NSNull *> *completed;

/**
 The Type of the Future, used for identifying kinds of the receiver.
 */
@property (nonatomic, copy, readonly) FBiOSTargetFutureType futureType;

@end

/**
 Creates a new operation.

 @param completed the completion future
 @param futureType the Future Type.
 @return a new Contiunation
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationNamed(FBFuture<NSNull *> *completed, FBiOSTargetFutureType futureType);

/**
 Re-Names an existing operation.
 Useful when a lower-level operation should be hoisted to a higher-level naming.

 @param operation the operation to wrap
 @param futureType the Future Type.
 @return a new Contiunation
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationRenamed(id<FBiOSTargetOperation> operation, FBiOSTargetFutureType futureType);

/**
 Makes a operation that has nothing left to do.

 @param futureType the Future Type.
 @return a new Contiunation.
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationDone(FBiOSTargetFutureType futureType);

/**
 A protocol that can be bridged to FBiOSTargetFutureDelegate
 */
@protocol FBiOSTargetFuture <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Receiver.
 */
@property (nonatomic, copy, class, readonly) FBiOSTargetFutureType futureType;

/**
 Starts the action represented by the receiver.

 @param target the target to run against.
 @param consumer the consumer to report binary data to.
 @param reporter the reporter to report structured data to.
 @return a Future wrapping the action type.
 */
- (FBFuture<FBiOSTargetFutureType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter;

@end

/**
 A base class for convenient FBiOSTargetFuture implementations.
 Most useful when there is an empty payload.
 */
@interface FBiOSTargetFutureSimple : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

@end

NS_ASSUME_NONNULL_END
