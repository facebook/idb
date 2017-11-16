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

#import "FBApplicationTestRunStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorResourceManager.h"
#import "FBSimulatorTestRunStrategy.h"
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

- (FBFuture<id<FBTerminationAwaitable>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger workingDirectory:self.simulator.auxillaryDirectory];
}

- (FBFuture<id<FBTerminationAwaitable>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger workingDirectory:(nullable NSString *)workingDirectory
{
  if (self.simulator.state != FBSimulatorStateBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator must be booted to run tests"]
      inSimulator:self.simulator]
      failFuture];
  }
  return (FBFuture<id<FBTerminationAwaitable>> *)[[FBSimulatorTestRunStrategy
    strategyWithTarget:self.simulator configuration:testLaunchConfiguration workingDirectory:workingDirectory reporter:reporter logger:logger]
    connectAndStart];
}

- (FBFuture<NSNull *> *)runApplicationTest:(FBApplicationTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter
{
  return [[FBApplicationTestRunStrategy
    strategyWithSimulator:self.simulator configuration:configuration reporter:reporter logger:self.simulator.logger]
    execute];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  NSError *error = nil;
  FBXCTestShimConfiguration *shims = [FBXCTestShimConfiguration defaultShimConfigurationWithError:&error];
  if (!shims) {
    return [FBFuture futureWithError:error];
  }
  FBXCTestDestination *destination = [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:self.simulator.deviceType.model version:self.simulator.osVersion.name];
  FBListTestConfiguration *configuration = [FBListTestConfiguration
    configurationWithDestination:destination
    shims:shims
    environment:@{}
    workingDirectory:self.simulator.auxillaryDirectory
    testBundlePath:bundlePath
    waitForDebugger:NO
    timeout:timeout];

  return [[FBListTestStrategy
    strategyWithExecutor:[FBSimulatorXCTestProcessExecutor executorWithSimulator:self.simulator configuration:configuration]
    configuration:configuration
    logger:self.simulator.logger]
    listTests];
}


@end
