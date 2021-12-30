/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBApplicationCommands>

/**
 Returns the mapping of group container to absolute path for a given simulator.

 @param simulator the simulator to obtain the path mapping for.
 @return a future wrapping the path mapping.
 */
+ (FBFuture<NSDictionary<NSString *, NSURL *> *> *)groupContainerToPathMappingForSimulator:(FBSimulator *)simulator;

/**
 Returns the mapping of application container to absolute path for a given simulator.

 @param simulator the simulator to obtain the path mapping for.
 @return a future wrapping the path mapping.
 */
+ (FBFuture<NSDictionary<NSString *, NSURL *> *> *)applicationContainerToPathMappingForSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
