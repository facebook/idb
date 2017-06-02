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
#import "FBXCTestContext.h"

static const NSTimeInterval ApplicationTestDefaultTimeout = 4000;

@interface FBApplicationTestRunner ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBApplicationTestConfiguration *configuration;
@property (nonatomic, strong, readonly) FBXCTestContext *context;

@end

@implementation FBApplicationTestRunner

+ (instancetype)iOSRunnerWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration context:context];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _context = context;

  return self;
}

- (BOOL)executeWithError:(NSError **)error
{
  FBApplicationDescriptor *testRunnerApp = [FBApplicationDescriptor userApplicationWithPath:self.configuration.runnerAppPath error:error];
  if (!testRunnerApp) {
    [self.context.logger logFormat:@"Failed to open test runner application: %@", *error];
    return NO;
  }

  if (![self.simulator installApplicationWithPath:testRunnerApp.path error:error]) {
    [self.context.logger logFormat:@"Failed to install test runner application: %@", *error];
    return NO;
  }

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:testRunnerApp
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  FBSimulatorTestRunStrategy *runner = [FBSimulatorTestRunStrategy
    strategyWithSimulator:self.simulator
    configuration:testLaunchConfiguration
    workingDirectory:[self.configuration.workingDirectory stringByAppendingPathComponent:@"tmp"]
    reporter:[FBXCTestReporterAdapter adapterWithReporter:self.context.reporter]];

  NSError *innerError = nil;
  FBTestManager *manager = [runner connectAndStartWithError:&innerError];
  if (!manager) {
    return [[[FBXCTestError
      describe:@"Failed to connect to the Simulator's Test Manager"]
      causedBy:innerError]
      failBool:error];
  }
  FBTestManagerResult *result = [manager waitUntilTestingHasFinishedWithTimeout:ApplicationTestDefaultTimeout];
  if (result.crashDiagnostic) {
    return [[FBXCTestError
      describeFormat:@"The Application Crashed during the Test Run\n%@", result.crashDiagnostic.asString]
      failBool:error];
  }
  if (result.error) {
    [self.context.logger logFormat:@"Failed to execute test bundle %@", result.error];
    return [XCTestBootstrapError failBoolWithError:result.error errorOut:error];
  }
  return YES;
}


@end
