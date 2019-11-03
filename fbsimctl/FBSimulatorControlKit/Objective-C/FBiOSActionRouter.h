/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTarget;

/**
 Routes Actions to Targets.
 */
@interface FBiOSActionRouter : NSObject

#pragma mark Initializers

/**
 A Router for the given target.
 Uses the default Action classes for the target.

 @param target the target to route actions for.
 @return a new Action Router.
 */
+ (instancetype)routerForTarget:(id<FBiOSTarget>)target;

/**
 A Router for the given target.
 Uses the provided Action Classes

 @param target the target to route actions for.
 @param actionClasses the Action Classes to use.
 @return a new Action Router.
 */
+ (instancetype)routerForTarget:(id<FBiOSTarget>)target actionClasses:(NSArray<Class> *)actionClasses;

/**
 The Default Action Classes.
 */
+ (NSArray<Class> *)defaultActionClasses;

#pragma mark Properties

/**
 The Target to Route to.
 */
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

/**
 A mapping of Action Type to the Class responsible for using it.
 */
@property (nonatomic, copy, readonly) NSDictionary<FBiOSTargetFutureType, Class> *actionMapping;

#pragma mark Serialization

/**
 Inflate a Target Action from JSON.

 @param json the JSON to inflate from
 @param error an error out for any error that occurs.
 @return a Target Action if successful, nil otherwise.
 */
- (nullable id<FBiOSTargetFuture>)actionFromJSON:(id)json error:(NSError **)error;

/**
 Deflate a Target Action to JSON, including the target.

 @param action the action to deflate.
 @return the Action JSON from the action.
 */
- (NSDictionary<NSString *, id> *)jsonFromAction:(id<FBiOSTargetFuture>)action;

/**
 Deflate a Target Action to JSON, excluding  the target.

 @param action the action to deflate.
 @return the Action JSON from the action.
 */
+ (NSDictionary<NSString *, id> *)jsonFromAction:(id<FBiOSTargetFuture>)action;

@end

NS_ASSUME_NONNULL_END
