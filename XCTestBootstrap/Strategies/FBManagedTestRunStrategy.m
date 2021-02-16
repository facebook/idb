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
#import "FBTestManagerTestReporter.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "XCTestBootstrapError.h"
#import "XCTestBootstrapFrameworkLoader.h"

@interface FBManagedTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

@property (nonatomic, strong, nullable, readonly) FBTestLaunchConfiguration *configuration;
@property (nonatomic, strong, nullable, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, nullable, readonly) id<FBXCTestPreparationStrategy> testPreparationStrategy;

@end

@implementation FBManagedTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategy:(id<FBXCTestPreparationStrategy>)testPreparationStrategy
{
  NSParameterAssert(target);

  return [[self alloc] initWithConfiguration:configuration target:target reporter:reporter logger:logger testPreparationStrategy:testPreparationStrategy];
}

- (instancetype)initWithConfiguration:(FBTestLaunchConfiguration *)configuration target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategy:(id<FBXCTestPreparationStrategy>)testPreparationStrategy
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _reporter = reporter;
  _target = target;
  _logger = logger;
  _testPreparationStrategy = testPreparationStrategy;

  return self;
}

#pragma mark Public Methods

- (FBFuture<FBFuture<NSNull *> *> *)connectAndStart
{
  NSParameterAssert(self.configuration.applicationLaunchConfiguration);
  NSParameterAssert(self.configuration.testBundlePath);

  NSError *error = nil;
  if (![XCTestBootstrapFrameworkLoader.allDependentFrameworks loadPrivateFrameworks:self.target.logger error:&error]) {
    return [XCTestBootstrapError failFutureWithError:error];
  }

  FBApplicationLaunchConfiguration *applicationLaunchConfiguration = self.configuration.applicationLaunchConfiguration;
  id<FBiOSTarget> target = self.target;
  id<FBTestManagerTestReporter> reporter = self.reporter;
  id<FBControlCoreLogger> logger = self.logger;

  return [[[self.testPreparationStrategy
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
      FBTestManagerContext *context = [FBTestManagerContext
        contextWithTestRunnerPID:launchedApplcation.processIdentifier
        testRunnerBundleID:runnerConfiguration.testRunner.bundleID
        sessionIdentifier:runnerConfiguration.sessionIdentifier];

      // Add callback for when the app under test exists
      [launchedApplcation.applicationTerminated onQueue:target.workQueue doOnResolved:^(NSNull *_) {
        [reporter appUnderTestExited];
      }];

      // Construct the mediator, the core of the test execution.
      FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
        mediatorWithContext:context
        target:target
        reporter:reporter
        logger:logger
        testedApplicationAdditionalEnvironment:runnerConfiguration.testedApplicationAdditionalEnvironment];

      return [[mediator
        connect]
        onQueue:target.workQueue fmap:^(id _) {
          FBFuture<NSNull *> *executionFinished = [[mediator
            execute]
            onQueue:target.workQueue respondToCancellation:^{
              return [mediator disconnect];
            }];
          return [FBFuture futureWithResult:executionFinished];
        }];
    }];
}

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
