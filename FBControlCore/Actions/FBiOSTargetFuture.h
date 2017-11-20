/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBEventReporter.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@protocol FBEventReporter;
@protocol FBiOSTarget;
@protocol FBiOSTargetFutureDelegate;
@protocol FBTerminationAwaitable;

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

@protocol FBiOSTargetFutureAwaitableDelegate;

/**
 A protocol that can be bridged to FBiOSTargetFutureDelegate
 */
@protocol FBiOSTargetFuture <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Reciever.
 */
@property (nonatomic, copy, readonly) FBiOSTargetFutureType actionType;

/**
 Starts the action represented by the reciever.

 @param target the target to run against.
 @param consumer the consumer to report binary data to.
 @param reporter the reporter to report structured data to.
 @param awaitableDelegate the delegate to report generated await-handles to.
 @return a Future wrapping the action type.
 */
- (FBFuture<FBiOSTargetFutureType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetFutureAwaitableDelegate>)awaitableDelegate;

@end

/**
 A Delegate for notifying of a long-running operation.
 */
@protocol FBiOSTargetFutureAwaitableDelegate

/**
 A Termination Handle of an Asynchronous Operation has been generated.

 @param action the action that the termination was generated for.
 @param target the target the handle was generated for.
 @param awaitable the generated termination awaitable.
 */
- (void)action:(id<FBiOSTargetFuture>)action target:(id<FBiOSTarget>)target didGenerateAwaitable:(id<FBTerminationAwaitable>)awaitable;

@end

/**
 A base class for convenient FBiOSTargetFuture implementations.
 Most useful when there is an empty payload.
 */
@interface FBiOSTargetFutureSimple : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

@end

NS_ASSUME_NONNULL_END
