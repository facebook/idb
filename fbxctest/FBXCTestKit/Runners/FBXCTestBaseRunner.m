/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestBaseRunner.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <sys/types.h>
#import <sys/stat.h>

#import "FBXCTestSimulatorFetcher.h"
#import "FBXCTestContext.h"

@interface FBXCTestBaseRunner ()

@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;
@property (nonatomic, strong, readonly) FBXCTestContext *context;

@end

@implementation FBXCTestBaseRunner

#pragma mark Initializers

+ (instancetype)testRunnerWithConfiguration:(FBXCTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  return [[self alloc] initWithConfiguration:configuration context:context];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _context = context;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)execute
{
  FBFuture<NSNull *> *future = [self.configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class] ? [self runiOSTest] : [self runMacTest];
  return [future
    onQueue:dispatch_get_main_queue() fmap:^(id _) {
      NSError *error = nil;
      if (![self.context.reporter printReportWithError:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)runMacTest
{
  FBMacDevice *device = [[FBMacDevice alloc] initWithLogger:self.context.logger];

  if ([self.configuration isKindOfClass:FBTestManagerTestConfiguration.class]) {
    return [[[FBTestRunStrategy strategyWithTarget:device configuration:(FBTestManagerTestConfiguration *)self.configuration reporter:self.context.reporter logger:self.context.logger testPreparationStrategyClass:FBMacTestPreparationStrategy.class] execute] onQueue:device.workQueue chain:^(FBFuture *future) {
      return [[device restorePrimaryDeviceState] fmapReplace:future];
    }];
  }

  id<FBXCTestProcessExecutor> executor = [FBMacXCTestProcessExecutor executorWithMacDevice:device configuration:self.configuration];
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[[FBListTestStrategy strategyWithExecutor:executor configuration:(FBListTestConfiguration *)self.configuration logger:self.context.logger] wrapInReporter:self.context.reporter] execute];
  }
  FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:self.context.reporter];
  return [[FBLogicTestRunStrategy strategyWithExecutor:executor configuration:(FBLogicTestConfiguration *)self.configuration reporter:adapter logger:self.context.logger] execute];
}

- (FBFuture<NSNull *> *)runiOSTest
{
  return [[self.context
    simulatorForiOSTestRun:self.configuration]
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulator *simulator) {
      return [[self
        runTestWithSimulator:simulator]
        onQueue:dispatch_get_main_queue() chain:^(FBFuture *future) {
          // Propogate the original result, but wait on the Simulator teardown as-well
          return [[self.context finishedExecutionOnSimulator:simulator] fmapReplace:future];
        }];
    }];
}

- (FBFuture<NSNull *> *)runTestWithSimulator:(FBSimulator *)simulator
{
  if ([self.configuration isKindOfClass:FBTestManagerTestConfiguration.class]) {
    return [[FBTestRunStrategy strategyWithTarget:simulator configuration:(FBTestManagerTestConfiguration *)self.configuration reporter:self.context.reporter logger:self.context.logger testPreparationStrategyClass:FBSimulatorTestPreparationStrategy.class] execute];
  }
  id<FBXCTestProcessExecutor> executor = [FBSimulatorXCTestProcessExecutor executorWithSimulator:simulator configuration:self.configuration];
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[[FBListTestStrategy strategyWithExecutor:executor configuration:(FBListTestConfiguration *)self.configuration logger:self.context.logger] wrapInReporter:self.context.reporter] execute];
  }
  FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:self.context.reporter];
  return [[FBLogicTestRunStrategy strategyWithExecutor:executor configuration:(FBLogicTestConfiguration *)self.configuration reporter:adapter logger:self.context.logger] execute];
}

@end
