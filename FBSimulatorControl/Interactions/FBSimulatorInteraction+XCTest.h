/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@class FBApplicationLaunchConfiguration;
@class FBTestBundle;

@interface FBSimulatorInteraction (XCTest)

/**
 Starts testing application using test bundle

 @param configuration configuration used to launch test runner application
 @param testBundlePath path to XCTest bundle used for testing
 @param workingDirectory xctest working directory
 @return the reciever, for chaining.
 */
- (instancetype)startTestRunnerLaunchConfiguration:(FBApplicationLaunchConfiguration *)configuration testBundlePath:(NSString *)testBundlePath workingDirectory:(NSString *)workingDirectory;

@end
