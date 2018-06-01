/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
+ (instancetype)forwarderWithTarget:(id<FBiOSTarget>)target commandClasses:(NSArray<Class> *)commandClasses statefulCommands:(NSSet<NSString *> *)statefulCommands;

@end

NS_ASSUME_NONNULL_END
