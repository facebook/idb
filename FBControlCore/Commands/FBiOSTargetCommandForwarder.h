/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol FBiOSTarget;
@protocol FBiOSTargetCommand;

/**
 A Helper for Command Forwarding, suitable for FBiOSTargets
 */
@interface FBiOSTargetCommandForwarder : NSObject

/**
 The Designated Initializer.

 @param commandClasses the classes to forward to.
 @param statefulCommands A set of stateful command class names that should be memoized.
 */
+ (nonnull instancetype)forwarderWithTarget:(nonnull id<FBiOSTarget>)target commandClasses:(nonnull NSArray<Class> *)commandClasses statefulCommands:(nonnull NSSet<Class> *)statefulCommands;

@end
