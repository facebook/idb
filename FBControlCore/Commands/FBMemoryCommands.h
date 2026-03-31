/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

/**
 Commands for simulating memory events.
 */
@protocol FBMemoryCommands <NSObject, FBiOSTargetCommand>

/**
 Simulates a memory warning

 @return a Future that resolves when successful.
 */
- (nonnull FBFuture<NSNull *> *)simulateMemoryWarning;

@end
