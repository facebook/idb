/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorXCTestCommands.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorXCTestProcessExecutor.h"

@interface FBSimulatorXCTestCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorXCTestCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark Public

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger workingDirectory:self.simulator.auxillaryDirectory];
}

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger workingDirectory:(nullable NSString *)workingDirectory
{
  if (self.simulator.state != FBSimulatorStateBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator must be booted to run tests"]
      inSimulator:self.simulator]
      failFuture];
  }
  FBSimulatorTestPreparationStrategy *testPreparationStrategy = [FBSimulatorTestPreparationStrategy
    strategyWithTestLaunchConfiguration:testLaunchConfiguration
    workingDirectory:workingDirectory];
  return (FBFuture<id<FBiOSTargetContinuation>> *) [[FBManagedTestRunStrategy
    strategyWithTarget:self.simulator configuration:testLaunchConfiguration reporter:reporter logger:logger testPreparationStrategy:testPreparationStrategy]
    connectAndStart];
}

- (FBFuture<NSNull *> *)runApplicationTest:(FBTestManagerTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter
{
  return [[FBTestRunStrategy
    strategyWithTarget:self.simulator configuration:configuration reporter:reporter logger:self.simulator.logger testPreparationStrategyClass:FBSimulatorTestPreparationStrategy.class]
    execute];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  return [[FBXCTestShimConfiguration
    defaultShimConfiguration]
    onQueue:self.simulator.workQueue fmap:^(FBXCTestShimConfiguration *shims) {
      FBListTestConfiguration *configuration = [FBListTestConfiguration
        configurationWithShims:shims
        environment:@{}
        workingDirectory:self.simulator.auxillaryDirectory
        testBundlePath:bundlePath
        runnerAppPath:nil
        waitForDebugger:NO
        timeout:timeout];

      return [[FBListTestStrategy
        strategyWithExecutor:[FBSimulatorXCTestProcessExecutor executorWithSimulator:self.simulator configuration:configuration]
        configuration:configuration
        logger:self.simulator.logger]
        listTests];
  }];
}


@end
