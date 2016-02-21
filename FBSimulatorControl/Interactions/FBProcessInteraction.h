/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@class FBProcessInfo;
@class FBSimulatorApplication;
@class FBSimulatorBinary;

/**
 Interactions for Processes.
 */
@interface FBProcessInteraction : FBSimulatorInteraction

/**
 Sends a signal(3) to the Process, verifying that is is a subprocess of the Simulator.

 @param signo the unix signo to send.
 @return an FBSimulatorInteraction for chaining.
 */
- (FBSimulatorInteraction *)signal:(int)signo;

/**
 SIGKILL's the provided Process, verifying that issignal: is a subprocess of the Simulator.

 @return an FBSimulatorInteraction for chaining.
 */
- (FBSimulatorInteraction *)kill;

@end

@interface FBSimulatorInteraction (FBProcessInteraction)

/**
 Creates a Process Interaction for the provided process.

 @param process the process to interact with. Must not be nil.
 @return a FBProcessInteraction
 */
- (FBProcessInteraction *)process:(FBProcessInfo *)process;

/**
 Creates a Process Interaction for the Application with the provided Application.

 @param application the process to interact with. Must not be nil.
 @return a FBProcessInteraction
 */
- (FBProcessInteraction *)applicationProcess:(FBSimulatorApplication *)application;

/**
 Creates a Process Interaction for the Application with the provided bundle id.

 @param bundleID the process to interact with. Must not be nil.
 @return a FBProcessInteraction
 */
- (FBProcessInteraction *)applicationProcessWithBundleID:(NSString *)bundleID;

/**
 Creates a Process Interaction for the Application with the Provided Binary.

 @param binary the process to interact with. Must not be nil.
 @return a FBProcessInteraction
 */
- (FBProcessInteraction *)agentProcess:(FBSimulatorBinary *)binary;

/**
 Creates a Process Interaction for the last-launched Application.

 @return a FBProcessInteraction
 */
- (FBProcessInteraction *)lastLaunchedApplication;

@end
