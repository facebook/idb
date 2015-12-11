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
 Helps make a more fluent API for interacting with Simulators.
 */
@interface FBSimulator (FBSimulatorInteraction)

/**
 Creates an `FBSimulatorInteraction` for the reciever.
 */
- (FBSimulatorInteraction *)interact;

@end
