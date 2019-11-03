/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestBaseRunner.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <sys/types.h>
#import <sys/stat.h>

#import "FBXCTestSimulatorFetcher.h"
#import "FBXCTestContext.h"
#import "FBXCTestCommandLine.h"
#import "FBXCTestDestination.h"

@interface FBXCTestBaseRunner ()

@property (nonatomic, strong, readonly) FBXCTestCommandLine *commandLine;
@property (nonatomic, strong, readonly) FBXCTestContext *context;

@end

@implementation FBXCTestBaseRunner

#pragma mark Initializers

+ (instancetype)testRunnerWithCommandLine:(FBXCTestCommandLine *)commandLine context:(FBXCTestContext *)context
{
  return [[self alloc] initWithCommandLine:commandLine context:context];
}

- (instancetype)initWithCommandLine:(FBXCTestCommandLine *)commandLine context:(FBXCTestContext *)context
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _commandLine = commandLine;
  _context = context;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)execute
{
  FBFuture<NSNull *> *future = [self.commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class] ? [self runiOSTest] : [self runMacTest];
  return [[future
    timeout:self.commandLine.globalTimeout waitingFor:@"entire test execution to finish"]
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (id _) {
      NSError *error = nil;
      if (![self.context.reporter printReportWithError:&error]) {
        return [FBFuture futureWithError:error];
      }
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (FBXCTestConfiguration *)configuration
{
  return self.commandLine.configuration;
}

- (FBFuture<NSNull *> *)runMacTest
{
  FBMacDevice *device = [[FBMacDevice alloc] initWithLogger:self.context.logger];

  if ([self.configuration isKindOfClass:FBTestManagerTestConfiguration.class]) {
    return [[[FBTestRunStrategy strategyWithTarget:device configuration:(FBTestManagerTestConfiguration *)self.configuration reporter:self.context.reporter logger:self.context.logger testPreparationStrategyClass:FBMacTestPreparationStrategy.class] execute] onQueue:device.workQueue chain:^(FBFuture *future) {
      return [[device restorePrimaryDeviceState] chainReplace:future];
    }];
  }

  id<FBXCTestProcessExecutor> executor = [FBMacXCTestProcessExecutor executorWithMacDevice:device shims:self.configuration.shims];
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[[FBListTestStrategy strategyWithExecutor:executor configuration:(FBListTestConfiguration *)self.configuration logger:self.context.logger] wrapInReporter:self.context.reporter] execute];
  }
  FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:self.context.reporter logger:self.context.logger];
  return [[FBLogicTestRunStrategy strategyWithExecutor:executor configuration:(FBLogicTestConfiguration *)self.configuration reporter:adapter logger:self.context.logger] execute];
}

- (FBFuture<NSNull *> *)runiOSTest
{
  return [[[self.context
    simulatorForCommandLine:self.commandLine]
    timeout:self.commandLine.testPreparationTimeout waitingFor:@"Simulator to be fetched for a test"]
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulator *simulator) {
      return [[self
        runTestWithSimulator:simulator]
        onQueue:dispatch_get_main_queue() chain:^(FBFuture *future) {
          // Propogate the original result, but wait on the Simulator teardown as-well
          return [[self.context finishedExecutionOnSimulator:simulator] chainReplace:future];
        }];
    }];
}

- (FBFuture<NSNull *> *)runTestWithSimulator:(FBSimulator *)simulator
{
  if ([self.configuration isKindOfClass:FBTestManagerTestConfiguration.class]) {
    return [[FBTestRunStrategy strategyWithTarget:simulator configuration:(FBTestManagerTestConfiguration *)self.configuration reporter:self.context.reporter logger:self.context.logger testPreparationStrategyClass:FBSimulatorTestPreparationStrategy.class] execute];
  }
  id<FBXCTestProcessExecutor> executor = [FBSimulatorXCTestProcessExecutor executorWithSimulator:simulator shims:self.configuration.shims];
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[[FBListTestStrategy strategyWithExecutor:executor configuration:(FBListTestConfiguration *)self.configuration logger:self.context.logger] wrapInReporter:self.context.reporter] execute];
  }
  FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:self.context.reporter logger:self.context.logger];
  return [[FBLogicTestRunStrategy strategyWithExecutor:executor configuration:(FBLogicTestConfiguration *)self.configuration reporter:adapter logger:self.context.logger] execute];
}

@end
