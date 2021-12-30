/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTarget;

/**
 A Protocol that defines a forwardable Commands Class.
 */
@protocol FBiOSTargetCommand <NSObject>

/**
 Instantiates the Commands instance.

 @param target the target to use.
 @return a new instance of the Command.
 */
+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target;

@end

@protocol FBiOSTarget;

/**
 A Helper for Command Forwarding, suitable for FBiOSTargets
 */
@interface FBiOSTargetCommandForwarder : NSObject

/**
 The Designated Initializer.

 @param commandClasses the classes to forward to.
 @param statefulCommands A set of stateful command class names that should be memoized.
 */
+ (instancetype)forwarderWithTarget:(id<FBiOSTarget>)target commandClasses:(NSArray<Class> *)commandClasses statefulCommands:(NSSet<Class> *)statefulCommands;

@end

NS_ASSUME_NONNULL_END
