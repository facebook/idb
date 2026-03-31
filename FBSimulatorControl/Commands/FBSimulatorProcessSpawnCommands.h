/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 An Implementation of FBProcessSpawnCommands for Simulators.
 */
@interface FBSimulatorProcessSpawnCommands : NSObject <FBProcessSpawnCommands>

#pragma mark Helpers

/**
 Builds the CoreSimulator launch Options for Launching an App or Process on a Simulator.

 @param arguments the arguments to use.
 @param environment the environment to use.
 @param waitForDebugger YES if the Application should be launched waiting for a debugger to attach. NO otherwise.
 @return a Dictionary of the Launch Options.
 */
+ (nonnull NSDictionary<NSString *, id> *)launchOptionsWithArguments:(nonnull NSArray<NSString *> *)arguments environment:(nonnull NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger;

@end
