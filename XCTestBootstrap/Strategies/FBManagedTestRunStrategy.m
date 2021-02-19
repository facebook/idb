/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBManagedTestRunStrategy.h"

#import "FBProductBundle.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerContext.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "FBXCTestReporter.h"
#import "XCTestBootstrapError.h"
#import "XCTestBootstrapFrameworkLoader.h"

@implementation FBManagedTestRunStrategy

#pragma mark Initializers

+ (FBFuture<NSNull *> *)runToCompletionWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter testPreparationStrategy:(id<FBXCTestPreparationStrategy>)testPreparationStrategy logger:(id<FBControlCoreLogger>)logger 
{
  NSParameterAssert(target);
  NSParameterAssert(configuration.applicationLaunchConfiguration);
  NSParameterAssert(configuration.testBundlePath);

  NSError *error = nil;
  if (![XCTestBootstrapFrameworkLoader.allDependentFrameworks loadPrivateFrameworks:target.logger error:&error]) {
    return [XCTestBootstrapError failFutureWithError:error];
  }

  FBApplicationLaunchConfiguration *applicationLaunchConfiguration = configuration.applicationLaunchConfiguration;
  return [[[testPreparationStrategy
    prepareTestWithIOSTarget:target]
    onQueue:target.workQueue fmap:^(FBTestRunnerConfiguration *runnerConfiguration) {
      FBApplicationLaunchConfiguration *applicationConfiguration = [self
        prepareApplicationLaunchConfiguration:applicationLaunchConfiguration
        withTestRunnerConfiguration:runnerConfiguration];
      return [[target
        launchApplication:applicationConfiguration]
        onQueue:target.workQueue map:^(id<FBLaunchedApplication> application) {
          return @[application, runnerConfiguration];
        }];
    }]
    onQueue:target.workQueue fmap:^(NSArray<id> *tuple) {
      id<FBLaunchedApplication> launchedApplcation = tuple[0];
      FBTestRunnerConfiguration *runnerConfiguration = tuple[1];

      // Make the Context for the Test Manager.
      FBTestManagerContext *context = [[FBTestManagerContext alloc]
        initWithTestRunnerPID:launchedApplcation.processIdentifier
        testRunnerBundleID:runnerConfiguration.testRunner.bundleID
        sessionIdentifier:runnerConfiguration.sessionIdentifier
        testedApplicationAdditionalEnvironment:runnerConfiguration.testedApplicationAdditionalEnvironment];

      // Add callback for when the app under test exists
      [launchedApplcation.applicationTerminated onQueue:target.workQueue doOnResolved:^(NSNull *_) {
        [reporter appUnderTestExited];
      }];

      // Construct and run the mediator, the core of the test execution.
      return [FBTestManagerAPIMediator
        connectAndRunUntilCompletionWithContext:context
        target:target
        reporter:reporter
        logger:logger];
    }];
}

+ (FBApplicationLaunchConfiguration *)prepareApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration withTestRunnerConfiguration:(FBTestRunnerConfiguration *)testRunnerConfiguration
{
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:testRunnerConfiguration.testRunner.bundleID
    bundleName:testRunnerConfiguration.testRunner.bundleID
    arguments:[self argumentsFromConfiguration:testRunnerConfiguration attributes:applicationLaunchConfiguration.arguments]
    environment:[self environmentFromConfiguration:testRunnerConfiguration environment:applicationLaunchConfiguration.environment]
    output:applicationLaunchConfiguration.output
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

+ (NSArray<NSString *> *)argumentsFromConfiguration:(FBTestRunnerConfiguration *)configuration attributes:(NSArray<NSString *> *)attributes
{
  return [(configuration.launchArguments ?: @[]) arrayByAddingObjectsFromArray:(attributes ?: @[])];
}

+ (NSDictionary<NSString *, NSString *> *)environmentFromConfiguration:(FBTestRunnerConfiguration *)configuration environment:(NSDictionary<NSString *, NSString *> *)environment
{
  NSMutableDictionary<NSString *, NSString *> *mEnvironment = (configuration.launchEnvironment ?: @{}).mutableCopy;
  if (environment) {
    [mEnvironment addEntriesFromDictionary:environment];
  }
  return [mEnvironment copy];
}

@end
