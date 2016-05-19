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

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlOperator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"

@implementation FBSimulatorInteraction (XCTest)

- (instancetype)startTestRunnerLaunchConfiguration:(FBApplicationLaunchConfiguration *)configuration testBundlePath:(NSString *)testBundlePath
{
  return [self startTestRunnerLaunchConfiguration:configuration testBundlePath:testBundlePath reporter:nil];
}

- (instancetype)startTestRunnerLaunchConfiguration:(FBApplicationLaunchConfiguration *)configuration testBundlePath:(NSString *)testBundlePath reporter:(id<FBTestManagerTestReporter>)reporter
{
  return [self startTestRunnerLaunchConfiguration:configuration testBundlePath:testBundlePath reporter:reporter workingDirectory:self.simulator.auxillaryDirectory];
}

- (instancetype)startTestRunnerLaunchConfiguration:(FBApplicationLaunchConfiguration *)configuration testBundlePath:(NSString *)testBundlePath reporter:(id<FBTestManagerTestReporter>)reporter workingDirectory:(NSString *)workingDirectory
{
  NSParameterAssert(configuration);
  NSParameterAssert(testBundlePath);
  NSParameterAssert(workingDirectory);
  [XCTestBootstrapFrameworkLoader initializeTestingEnvironment];

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBSimulatorTestPreparationStrategy *testPrepareStrategy = [FBSimulatorTestPreparationStrategy
      strategyWithTestRunnerBundleID:configuration.bundleID
      testBundlePath:testBundlePath
      workingDirectory:workingDirectory];
    FBSimulatorControlOperator *operator = [FBSimulatorControlOperator operatorWithSimulator:self.simulator];
    FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy
      strategyWithDeviceOperator:operator
      testPrepareStrategy:testPrepareStrategy
      reporter:reporter
      logger:simulator.logger];

    NSError *innerError = nil;
    FBTestManager *testManager = [testRunStrategy startTestManagerWithAttributes:configuration.arguments environment:configuration.environment error:&innerError];
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

@end
