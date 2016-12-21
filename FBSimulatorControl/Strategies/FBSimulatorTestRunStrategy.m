/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTestRunStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBSimulator+Private.h"
#import "FBSimulatorControlOperator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorResourceManager.h"

@interface FBSimulatorTestRunStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@property (nonatomic, strong, nullable, readonly) FBTestLaunchConfiguration *configuration;
@property (nonatomic, copy, nullable, readonly) NSString *workingDirectory;
@property (nonatomic, strong, nullable, readonly) id<FBTestManagerTestReporter> reporter;

@end

@implementation FBSimulatorTestRunStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator configuration:(nullable FBTestLaunchConfiguration *)configuration  workingDirectory:(nullable NSString *)workingDirectory reporter:(nullable id<FBTestManagerTestReporter>)reporter
{
  NSParameterAssert(simulator);

  return [[self alloc] initWithConfiguration:configuration simulator:simulator workingDirectory:workingDirectory reporter:reporter];
}

- (instancetype)initWithConfiguration:(FBTestLaunchConfiguration *)configuration simulator:(FBSimulator *)simulator workingDirectory:(NSString *)workingDirectory reporter:(id<FBTestManagerTestReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _reporter = reporter;
  _workingDirectory = workingDirectory;
  _simulator = simulator;

  return self;
}

- (nullable instancetype)connectAndStartWithError:(NSError **)error
{
  NSParameterAssert(self.configuration.applicationLaunchConfiguration);
  NSParameterAssert(self.configuration.testBundlePath);
  NSParameterAssert(self.workingDirectory);

  NSError *innerError = nil;
  FBSimulator *simulator = self.simulator;

  if (![XCTestBootstrapFrameworkLoader loadPrivateFrameworks:simulator.logger error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  if (simulator.state != FBSimulatorStateBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator must be booted to run tests"]
      inSimulator:simulator]
      fail:error];
  }

  FBSimulatorTestPreparationStrategy *testPrepareStrategy = [FBSimulatorTestPreparationStrategy
    strategyWithTestLaunchConfiguration:self.configuration
    workingDirectory:self.workingDirectory];
  FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy
    strategyWithIOSTarget:simulator
    testPrepareStrategy:testPrepareStrategy
    reporter:self.reporter
    logger:simulator.logger];

  FBTestManager *testManager = [testRunStrategy
    startTestManagerWithAttributes:self.configuration.applicationLaunchConfiguration.arguments
    environment:self.configuration.applicationLaunchConfiguration.environment
    error:&innerError];

  if (!testManager) {
    return [[[FBSimulatorError
      describeFormat:@"Failed start test manager"]
      causedBy:innerError]
      fail:error];
  }
  [simulator.eventSink testmanagerDidConnect:testManager];
  return self;
}

- (FBTestManagerResult *)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout
{
  for (FBTestManager *testManager in self.simulator.resourceSink.testManagers.copy) {
    FBTestManagerResult *result = [testManager waitUntilTestingHasFinishedWithTimeout:timeout];
    if (!result.didEndSuccessfully) {
      return result;
    }
  }
  return FBTestManagerResult.success;
}

@end
