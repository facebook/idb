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

/**
 An implementation of FBFileCommands for Simulators
 */
@interface FBSimulatorFileCommands : NSObject <FBFileCommands, FBiOSTargetCommand>

/**
 Creates and returns a fiile container for the provided path mapping.

 @param pathMapping the path mapping to use.
 @param queue the queue to use.
 @return a file container for the provided path mapping.
 */
+ (id<FBFileContainer>)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping queue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
