/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBUITestRunStrategy.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

static const NSTimeInterval ApplicationTestDefaultTimeout = 4000;

@interface FBUITestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) FBUITestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readonly) Class<FBXCTestPreparationStrategy> testPreparationStrategyClass;
@end

@implementation FBUITestRunStrategy

+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)target configuration:(FBUITestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategyClass:(Class<FBXCTestPreparationStrategy>)testPreparationStrategyClass
{
  return [[self alloc] initWithTarget:target configuration:configuration reporter:reporter logger:logger testPreparationStrategyClass:testPreparationStrategyClass];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target configuration:(FBUITestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategyClass:(Class<FBXCTestPreparationStrategy>)testPreparationStrategyClass
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _configuration = configuration;
  _reporter = reporter;
  _logger = logger;
  _testPreparationStrategyClass = testPreparationStrategyClass;
  return self;
}

#pragma mark FBXCTestRunner

- (FBFuture<NSNull *> *)execute
{
  NSError *error = nil;
  FBApplicationBundle *testRunnerApp = [FBApplicationBundle applicationWithPath:self.configuration.runnerAppPath error:&error];
  if (!testRunnerApp) {
    [self.logger logFormat:@"Failed to open test runner application: %@", error];
    return [FBFuture futureWithError:error];
  }

  FBApplicationBundle *testTargetApp;
  if (self.configuration.testTargetAppPath) {
    testTargetApp = [FBApplicationBundle applicationWithPath:self.configuration.testTargetAppPath error:&error];
    if (!testTargetApp) {
      [self.logger logFormat:@"Failed to open test target application: %@", error];
      return [FBFuture futureWithError:error];
    }
  }

  return [[[self.target
    installApplicationWithPath:testRunnerApp.path]
    onQueue:self.target.workQueue fmap:^(id _) {
      return [self startUITestWithTestRunnerApp:testRunnerApp testTargetApp:testTargetApp];
    }]
    timedOutIn:ApplicationTestDefaultTimeout];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startUITestWithTestRunnerApp:(FBApplicationBundle *)testRunnerApp testTargetApp:(FBApplicationBundle *)testTargetApp
{
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:testRunnerApp
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  if (testTargetApp) {
    testLaunchConfiguration = [[[testLaunchConfiguration
     withTargetApplicationPath:testTargetApp.path]
     withTargetApplicationBundleID:testTargetApp.bundleID]
     withUITesting:YES];
  }

  id<FBXCTestPreparationStrategy> testPreparationStrategy = [self.testPreparationStrategyClass
    strategyWithTestLaunchConfiguration:testLaunchConfiguration
    workingDirectory:[self.configuration.workingDirectory stringByAppendingPathComponent:@"tmp"]];

  FBSimulatorTestRunStrategy *runner = [FBSimulatorTestRunStrategy
    strategyWithTarget:self.target
    configuration:testLaunchConfiguration
    reporter:[FBXCTestReporterAdapter adapterWithReporter:self.reporter]
    logger:self.target.logger
    testPreparationStrategy:testPreparationStrategy];

  return [[[runner
    connectAndStart]
    onQueue:self.target.workQueue fmap:^(FBTestManager *manager) {
      return [manager execute];
    }]
    onQueue:self.target.workQueue fmap:^(FBTestManagerResult *result) {
      if (result.crashDiagnostic) {
        return [[FBXCTestError
          describeFormat:@"The Application Crashed during the Test Run\n%@", result.crashDiagnostic.asString]
          failFuture];
      }
      if (result.error) {
        [self.logger logFormat:@"Failed to execute test bundle %@", result.error];
        return [FBFuture futureWithError:result.error];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

@end
