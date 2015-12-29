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

/**
 Interactions for the Lifecycle of the Simulator.
 */
@interface FBSimulatorInteraction (Lifecycle)

/**
 Boots the Simulator.

 @return the reciever, for chaining.
 */
- (instancetype)bootSimulator;

/**
 Shuts the Simulator down.

 @return the reciever, for chaining.
 */
- (instancetype)shutdownSimulator;

/**
 Opens the provided URL on the Simulator.

 @param url the URL to open.
 @return the reciever, for chaining.
 */
- (instancetype)openURL:(NSURL *)url;

@end
