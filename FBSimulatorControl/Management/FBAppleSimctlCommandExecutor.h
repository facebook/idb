/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorSet;

@protocol FBControlCoreLogger;
@protocol FBDataConsumer;

/**
 A command executor for 'simctl'
 */
@interface FBAppleSimctlCommandExecutor : NSObject

#pragma mark Initializers

/**
 Constructs an Executor for a given simulator.

 @param simulator the simulator to execute on
 @return a new command executor
 */
+ (instancetype)executorForSimulator:(FBSimulator *)simulator;

/**
 Constructs an Executor for a given simulator set.

 @param set the simulator to execute against.
 @return a new command executor
 */
+ (instancetype)executorForDeviceSet:(FBSimulatorSet *)set;

#pragma mark Public Methods

/**
 Constructs a task builder.

 @param command the command name.
 @param arguments the arguments of the command.
 */
- (FBTaskBuilder<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *)taskBuilderWithCommand:(NSString *)command arguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
