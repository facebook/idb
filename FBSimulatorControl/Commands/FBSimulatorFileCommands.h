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
 An implementation of FBFileContainer for simulators.
 */
@interface FBSimulatorFileContainer : NSObject <FBFileContainer>

/**
 The Designated Initializer.

 @param containerPath the container path to use.
 @param queue the queue to perform work on.
 @return a new instance.
 */
- (instancetype)initWithContainerPath:(NSString *)containerPath queue:(dispatch_queue_t)queue;

@end

/**
 An implementation of FBFileCommands for Simulators
 */
@interface FBSimulatorFileCommands : NSObject <FBFileCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
