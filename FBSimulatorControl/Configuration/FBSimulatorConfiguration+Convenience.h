/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorConfiguration.h>

/**
 Some conveniences that make it easier to manipulate Simulator Configurations
 */
@interface FBSimulatorConfiguration (Convenience)

/**
 Returns a new Simulator Configuration, for the oldest available OS for the current SDK.
 */
+ (instancetype)oldestAvailableOS;

/**
 Returns a new Simulator Configuration, for the newest available OS for the current SDK.
 */
+ (instancetype)newestAvailableOS;

/**
 An NSArray<FBSimulatorConfiguration> for available runtimes, sorted by oldest to newest.
 */
+ (NSArray *)orderedOSVersionRuntimes;

@end
