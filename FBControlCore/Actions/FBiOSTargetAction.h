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
@protocol FBiOSTargetActionDelegate;
@protocol FBTerminationAwaitable;

/**
 An extensible string enum representing an Action Type.
 */
typedef NSString *FBiOSTargetActionType NS_EXTENSIBLE_STRING_ENUM;

/**
 The Action Type for an Application Launch.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeApplicationLaunch;

/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeAgentLaunch;

/**
 The Action Type for a Test Launch.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeTestLaunch;

/**
 A Protocol that defines a fully serializable action that can be performed on an FBiOSTarget Instance.
 */
@protocol FBiOSTargetAction <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Reciever.
 */
@property (nonatomic, copy, readonly) FBiOSTargetActionType actionType;

/**
 Runs the Action.

 @param target the target to run against.
 @param delegate the delegate to be notified.
 @param error an error out for any error that occurs.
 */
- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error;

@end

/**
 A Delegate for notifying of a long-running operation.
 */
@protocol FBiOSTargetActionAwaitableDelegate

/**
 A Termination Handle of an Asynchronous Operation has been generated.

 @param action the action that the termination was generated for.
 @param target the target the handle was generated for.
 @param awaitable the generated termination awaitable.
 */
- (void)action:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target didGenerateAwaitable:(id<FBTerminationAwaitable>)awaitable;

@end

/**
 A Delegate that recieves information about the lifecycle of a Target Action.
 */
@protocol FBiOSTargetActionDelegate <NSObject, FBEventReporter, FBiOSTargetActionAwaitableDelegate>


/**
 Provide the File Consumer for a given Action & Target.

 @param action the action that the termination was generated for.
 @param target the target the handle was generated for.
 @return the Output File Consumer
 */
- (id<FBFileConsumer>)obtainConsumerForAction:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target;

@end

/**
 A protocol that can be bridged to FBiOSTargetActionDelegate
 */
@protocol FBiOSTargetFuture <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Reciever.
 */
@property (nonatomic, copy, readonly) FBiOSTargetActionType actionType;

/**
 Starts the action represented by the reciever.

 @param target the target to run against.
 @param consumer the consumer to report binary data to.
 @param reporter the reporter to report structured data to.
 @param awaitableDelegate the delegate to report generated await-handles to.
 @return a Future wrapping the action type.
 */
- (FBFuture<FBiOSTargetActionType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetActionAwaitableDelegate>)awaitableDelegate;

@end

/**
 Bridges an FBiOSTargetFuture to an FBiOSTargetAction
 */
extern id<FBiOSTargetAction> FBiOSTargetActionFromTargetFuture(id<FBiOSTargetFuture> targetFuture);

/**
 A base class for convenient FBiOSTargetAction implementations.
 Most useful when there is an empty payload.
 */
@interface FBiOSTargetActionSimple : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

@end

NS_ASSUME_NONNULL_END
