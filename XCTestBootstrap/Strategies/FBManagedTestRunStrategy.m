/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBManagedTestRunStrategy.h"

#import "FBTestManager.h"
#import "FBXCTestRunStrategy.h"
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

- (FBFuture<FBTestManager *> *)connectAndStart
{
  NSParameterAssert(self.configuration.applicationLaunchConfiguration);
  NSParameterAssert(self.configuration.testBundlePath);

  NSError *error = nil;
  if (![XCTestBootstrapFrameworkLoader.allDependentFrameworks loadPrivateFrameworks:self.target.logger error:&error]) {
    return [XCTestBootstrapError failFutureWithError:error];
  }

  FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy
    strategyWithIOSTarget:self.target
    testPrepareStrategy:self.testPreparationStrategy
    reporter:self.reporter
    logger:self.logger];

  return [[testRunStrategy
    startTestManagerWithApplicationLaunchConfiguration:self.configuration.applicationLaunchConfiguration]
    onQueue:self.target.workQueue fmap:^(FBTestManager *testManager) {
      FBFuture<FBTestManagerResult *> *result = [testManager execute];
      if (result.error) {
        return [FBFuture futureWithError:result.error];
      }
      return [FBFuture futureWithResult:testManager];
    }];
}

@end
