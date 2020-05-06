/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestRunStrategy.h"

#import <Foundation/Foundation.h>
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBControlCore/FBControlCore.h>

#import "FBProductBundle.h"
#import "FBTestManager.h"
#import "FBTestManagerContext.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "XCTestBootstrapError.h"

@interface FBXCTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> iosTarget;
@property (nonatomic, strong, readonly) id<FBXCTestPreparationStrategy> prepareStrategy;
@property (nonatomic, strong, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithIOSTarget:(id<FBiOSTarget>)iosTarget testPrepareStrategy:(id<FBXCTestPreparationStrategy>)testPrepareStrategy reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithIOSTarget:iosTarget testPrepareStrategy:testPrepareStrategy reporter:reporter logger:logger];
}

- (instancetype)initWithIOSTarget:(id<FBiOSTarget>)iosTarget testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _iosTarget = iosTarget;
  _prepareStrategy = prepareStrategy;
  _reporter = reporter;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<FBTestManager *> *)startTestManagerWithApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  NSAssert(self.iosTarget, @"iOS Target is needed to perform meaningful test");
  NSAssert(self.prepareStrategy, @"Test preparation strategy is needed to perform meaningful test");

  return [[[self.prepareStrategy
    prepareTestWithIOSTarget:self.iosTarget]
    onQueue:self.iosTarget.workQueue fmap:^(FBTestRunnerConfiguration *runnerConfiguration) {
      FBApplicationLaunchConfiguration *applicationConfiguration = [self
        prepareApplicationLaunchConfiguration:applicationLaunchConfiguration
        withTestRunnerConfiguration:runnerConfiguration];
      return [[self.iosTarget
        launchApplication:applicationConfiguration]
        onQueue:self.iosTarget.workQueue map:^(id<FBLaunchedProcess> process) {
          return @[process, runnerConfiguration];
        }];
    }]
    onQueue:self.iosTarget.workQueue fmap:^(NSArray<id> *tuple) {
      id<FBLaunchedProcess> applicationProcess = tuple[0];
      FBTestRunnerConfiguration *runnerConfiguration = tuple[1];

      // Make the Context for the Test Manager.
      FBTestManagerContext *context = [FBTestManagerContext
        contextWithTestRunnerPID:applicationProcess.processIdentifier
        testRunnerBundleID:runnerConfiguration.testRunner.bundleID
        sessionIdentifier:runnerConfiguration.sessionIdentifier];

      // Attach to the XCTest Test Runner host Process.
      FBTestManager *testManager = [FBTestManager
        testManagerWithContext:context
        iosTarget:self.iosTarget
        reporter:self.reporter
        logger:self.logger
        testedApplicationAdditionalEnvironment:runnerConfiguration.testedApplicationAdditionalEnvironment];

      // Add callback for when the app under test exists
      [[applicationProcess exitCode] onQueue:self.iosTarget.workQueue doOnResolved:^(NSNumber * _) {
        [self.reporter appUnderTestExited];
      }];

      return [[testManager
        connect]
        onQueue:self.iosTarget.workQueue fmap:^(FBTestManagerResult *result) {
          if (result.error) {
            return [FBFuture futureWithError:result.error];
          }
          return [FBFuture futureWithResult:testManager];
      }];
    }];
}

#pragma mark Private

- (FBApplicationLaunchConfiguration *)prepareApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration withTestRunnerConfiguration:(FBTestRunnerConfiguration *)testRunnerConfiguration
{
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:testRunnerConfiguration.testRunner.bundleID
    bundleName:testRunnerConfiguration.testRunner.bundleID
    arguments:[self argumentsFromConfiguration:testRunnerConfiguration attributes:applicationLaunchConfiguration.arguments]
    environment:[self environmentFromConfiguration:testRunnerConfiguration environment:applicationLaunchConfiguration.environment]
    output:applicationLaunchConfiguration.output
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

- (NSArray<NSString *> *)argumentsFromConfiguration:(FBTestRunnerConfiguration *)configuration attributes:(NSArray<NSString *> *)attributes
{
  return [(configuration.launchArguments ?: @[]) arrayByAddingObjectsFromArray:(attributes ?: @[])];
}

- (NSDictionary<NSString *, NSString *> *)environmentFromConfiguration:(FBTestRunnerConfiguration *)configuration environment:(NSDictionary<NSString *, NSString *> *)environment
{
  NSMutableDictionary<NSString *, NSString *> *mEnvironment = (configuration.launchEnvironment ?: @{}).mutableCopy;
  if (environment) {
    [mEnvironment addEntriesFromDictionary:environment];
  }
  return [mEnvironment copy];
}

@end
