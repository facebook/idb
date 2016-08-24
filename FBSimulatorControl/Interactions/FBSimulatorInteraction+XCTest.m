/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+XCTest.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBSimulator+Private.h"
#import "FBSimulatorControlOperator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorResourceManager.h"

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
  NSParameterAssert(testLaunchConfiguration.applicationLaunchConfiguration);
  NSParameterAssert(testLaunchConfiguration.testBundlePath);
  NSParameterAssert(workingDirectory);
  [XCTestBootstrapFrameworkLoader loadPrivateFrameworksOrAbort];

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBSimulatorTestPreparationStrategy *testPrepareStrategy = [FBSimulatorTestPreparationStrategy
      strategyWithTestLaunchConfiguration:testLaunchConfiguration
      workingDirectory:workingDirectory];
    FBSimulatorControlOperator *operator = [FBSimulatorControlOperator operatorWithSimulator:self.simulator];
    FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy
      strategyWithDeviceOperator:operator
      testPrepareStrategy:testPrepareStrategy
      reporter:reporter
      logger:simulator.logger];

    NSError *innerError = nil;
    FBTestManager *testManager = [testRunStrategy startTestManagerWithAttributes:testLaunchConfiguration.applicationLaunchConfiguration.arguments
                                                                     environment:testLaunchConfiguration.applicationLaunchConfiguration.environment
                                                                           error:&innerError];
    if (!testManager) {
      return [[[FBSimulatorError
        describeFormat:@"Failed start test manager"]
        causedBy:innerError]
        failBool:error];
    }
    [simulator.eventSink testmanagerDidConnect:testManager];

    return YES;
  }];
}

- (instancetype)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    for (FBTestManager *testManager in simulator.resourceSink.testManagers.copy) {
      if (![testManager waitUntilTestingHasFinishedWithTimeout:timeout]) {
        return [[FBSimulatorError
                 describeFormat:@"Timeout waiting for test to finish"]
                failBool:error];
      }
    }
    return YES;
  }];
}

@end
