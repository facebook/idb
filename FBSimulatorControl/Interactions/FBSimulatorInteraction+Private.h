/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@class FBProcessInfo;
@class FBSimulatorBinary;

@interface FBSimulatorInteraction ()

@property (nonatomic, strong) FBSimulator *simulator;

/**
 Chains an interaction on an process, for the given application.

 @param binary the binary to interact with.
 @param block the block to execute with the process.
 @return the reciever, for chaining.
 */
- (instancetype)binary:(FBSimulatorBinary *)binary interact:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block;

/**
 Interact with a Shutdown Simulator. Will ensure that the Simulator is in the appropriate state.

 @param block the block to execute with the Shutdown Simulator.
 @return the reciever, for chaining.
 */
- (instancetype)interactWithShutdownSimulator:(BOOL (^)(NSError **error, FBSimulator *simulator))block;

/**
 Interact with a Shutdown Simulator. Will ensure that the Simulator is in the appropriate state.s

 @param block the block to execute with the Shutdown Simulator.
 @return the reciever, for chaining.
 */
- (instancetype)interactWithBootedSimulator:(BOOL (^)(NSError **error, FBSimulator *simulator))block;

@end
