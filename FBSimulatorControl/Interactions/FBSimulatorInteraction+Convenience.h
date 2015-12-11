/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

/**
 Some conveniences for making the interactions associated with a Simulator Configuration.
 */
@interface FBSimulatorInteraction (Convenience)

/**
 Makes an interaction by:
 1) Setting the Locale (if the configuration contains one)
 2) Sets up the keyboard

 @param configuration the configuration to apply.
 */
- (instancetype)configureWith:(FBSimulatorConfiguration *)configuration;

@end

/**
 Helps make a more fluent API for interacting with Simulators.
 */
@interface FBSimulator (FBSimulatorInteraction)

/**
 Creates an `FBSimulatorInteraction` for the reciever.
 */
- (FBSimulatorInteraction *)interact;

@end
