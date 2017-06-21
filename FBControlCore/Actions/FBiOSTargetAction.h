/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@protocol FBiOSTarget;
@protocol FBiOSTargetActionDelegate;
@protocol FBTerminationHandle;

/**
 An extensible string enum representing an Action Type.
 */
typedef NSString *FBiOSTargetActionType NS_EXTENSIBLE_STRING_ENUM;

/**
 A Protocol that defines a fully serializable action that can be performed on an FBiOSTarget Instance.
 */
@protocol FBiOSTargetAction <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Reciever.
 */
@property (nonatomic, class, copy, readonly) FBiOSTargetActionType actionType;

/**
 Runs the Action.

 @param target the target to run against.
 @param delegate the delegate to be notified.
 @param error an error out for any error that occurs.
 */
- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error;

@end

/**
 A Delegate that recieves information about the lifecycle of a Target Action.
 */
@protocol FBiOSTargetActionDelegate <NSObject>

/**
 A Termination Handle of an Asynchronous Operation has been generated.

 @param action the action that the termination was generated for.
 @param target the target the handle was generated for.
 @param terminationHandle the generated termination handle.
 */
- (void)action:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target didGenerateTerminationHandle:(id<FBTerminationHandle>)terminationHandle;

/**
 Provide the File Consumer for a given Action & Target.

 @param action the action that the termination was generated for.
 @param target the target the handle was generated for.
 @return the Output File Consumer
 */
- (id<FBFileConsumer>)obtainConsumerForAction:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target ;

@end

NS_ASSUME_NONNULL_END
