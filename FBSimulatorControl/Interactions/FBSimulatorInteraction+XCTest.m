/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+XCTest.h"

#import "FBSimulatorTestRunStrategy.h"
#import "FBSimulatorInteraction+Private.h"

@implementation FBSimulatorInteraction (XCTest)

- (instancetype)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:nil];
}

- (instancetype)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBTestManagerTestReporter>)reporter
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter workingDirectory:self.simulator.auxillaryDirectory];
}

- (instancetype)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBTestManagerTestReporter>)reporter workingDirectory:(NSString *)workingDirectory
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBSimulatorTestRunStrategy
      strategyWithSimulator:simulator configuration:testLaunchConfiguration workingDirectory:workingDirectory reporter:reporter]
      connectAndStartWithError:error] != nil;
  }];
}

- (instancetype)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBSimulatorTestRunStrategy
      strategyWithSimulator:simulator configuration:nil workingDirectory:nil reporter:nil]
      waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:timeout error:error] != nil;
  }];
}

@end
