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

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

@property (nonatomic, strong, nullable, readonly) FBTestLaunchConfiguration *configuration;
@property (nonatomic, copy, nullable, readonly) NSString *workingDirectory;
@property (nonatomic, strong, nullable, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration  workingDirectory:(NSString *)workingDirectory reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(target);

  return [[self alloc] initWithConfiguration:configuration target:target workingDirectory:workingDirectory reporter:reporter logger:logger];
}

- (instancetype)initWithConfiguration:(FBTestLaunchConfiguration *)configuration target:(id<FBiOSTarget>)target workingDirectory:(NSString *)workingDirectory reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _reporter = reporter;
  _workingDirectory = workingDirectory;
  _target = target;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<FBTestManager *> *)connectAndStart
{
  NSParameterAssert(self.configuration.applicationLaunchConfiguration);
  NSParameterAssert(self.configuration.testBundlePath);
  NSParameterAssert(self.workingDirectory);

  NSError *error = nil;
  if (![XCTestBootstrapFrameworkLoader.allDependentFrameworks loadPrivateFrameworks:self.target.logger error:&error]) {
    return [FBSimulatorError failFutureWithError:error];
  }

  FBSimulatorTestPreparationStrategy *testPrepareStrategy = [FBSimulatorTestPreparationStrategy
    strategyWithTestLaunchConfiguration:self.configuration
    workingDirectory:self.workingDirectory];
  FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy
    strategyWithIOSTarget:self.target
    testPrepareStrategy:testPrepareStrategy
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
