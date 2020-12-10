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
typedef NSString *FBiOSTargetOperationType NS_EXTENSIBLE_STRING_ENUM;

/**
 The Action Type for an Application Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeApplicationLaunch;

/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeAgentLaunch;

/**
 The Action Type for a Test Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeTestLaunch;

/**
 The Action Type for Log Tails.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeLogTail;

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
@property (nonatomic, copy, readonly) FBiOSTargetOperationType operationType;

@end

/**
 Creates a new operation.

 @param completed the completion future
 @param operationType the Future Type.
 @return a new Contiunation
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationNamed(FBFuture<NSNull *> *completed, FBiOSTargetOperationType operationType);

/**
 Re-Names an existing operation.
 Useful when a lower-level operation should be hoisted to a higher-level naming.

 @param operation the operation to wrap
 @param operationType the Future Type.
 @return a new Contiunation
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationRenamed(id<FBiOSTargetOperation> operation, FBiOSTargetOperationType operationType);

/**
 Makes a operation that has nothing left to do.

 @param operationType the Future Type.
 @return a new Contiunation.
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationDone(FBiOSTargetOperationType operationType);

/**
 A protocol that can be bridged to FBiOSTargetFutureDelegate
 */
@protocol FBiOSTargetFuture <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Receiver.
 */
@property (nonatomic, copy, class, readonly) FBiOSTargetOperationType operationType;

/**
 Starts the action represented by the receiver.

 @param target the target to run against.
 @param consumer the consumer to report binary data to.
 @param reporter the reporter to report structured data to.
 @return a Future wrapping the action type.
 */
- (FBFuture<FBiOSTargetOperationType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter;

@end

/**
 A base class for convenient FBiOSTargetFuture implementations.
 Most useful when there is an empty payload.
 */
@interface FBiOSTargetFutureSimple : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

@end

NS_ASSUME_NONNULL_END
