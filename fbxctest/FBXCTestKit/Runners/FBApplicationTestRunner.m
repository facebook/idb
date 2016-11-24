/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationTestRunner.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestLogger.h"
#import "FBXCTestReporterAdapter.h"
#import "FBXCTestError.h"

static const NSTimeInterval ApplicationTestDefaultTimeout = 4000;

@interface FBApplicationTestRunner ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBApplicationTestConfiguration *configuration;

@end

@implementation FBApplicationTestRunner

+ (instancetype)withSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;

  return self;
}

- (BOOL)runTestsWithError:(NSError **)error
{
  FBApplicationDescriptor *testRunnerApp = [FBApplicationDescriptor userApplicationWithPath:self.configuration.runnerAppPath error:error];
  if (!testRunnerApp) {
    [self.configuration.logger logFormat:@"Failed to open test runner application: %@", *error];
    return NO;
  }

  if (![[self.simulator.interact installApplication:testRunnerApp] perform:error]) {
    [self.configuration.logger logFormat:@"Failed to install test runner application: %@", *error];
    return NO;
  }

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:testRunnerApp
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    options:0];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  FBSimulatorTestRunStrategy *runner = [FBSimulatorTestRunStrategy
    strategyWithSimulator:self.simulator
    configuration:testLaunchConfiguration
    workingDirectory:[self.configuration.workingDirectory stringByAppendingPathComponent:@"tmp"]
    reporter:[FBXCTestReporterAdapter adapterWithReporter:self.configuration.reporter]];

  NSError *innerError = nil;
  if (![runner connectAndStartWithError:&innerError]) {
    return [[[FBXCTestError
      describe:@"Failed to connect to the Simulator's Test Manager"]
      causedBy:innerError]
      failBool:error];
  }
  FBTestManagerResult *result = [runner waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:ApplicationTestDefaultTimeout];
  if (result.crashDiagnostic) {
    return [[FBXCTestError
      describeFormat:@"The Application Crashed during the Test Run\n%@", result.crashDiagnostic.asString]
      failBool:error];
  }
  if (result.error) {
    [self.configuration.logger logFormat:@"Failed to execute test bundle %@", result.error];
    return [XCTestBootstrapError failBoolWithError:result.error errorOut:error];
  }
  return YES;
}


@end
