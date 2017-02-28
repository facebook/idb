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

#import "FBSimulatorTestRunStrategy.h"
#import "FBSimulatorError.h"
#import "FBSimulator.h"

@interface FBSimulatorXCTestCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorXCTestCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
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

- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration error:(NSError **)error
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:nil error:error];
}

- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter error:(NSError **)error
{
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter workingDirectory:self.simulator.auxillaryDirectory error:error];
}

- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter workingDirectory:(nullable NSString *)workingDirectory error:(NSError **)error
{
  return [[FBSimulatorTestRunStrategy
    strategyWithSimulator:self.simulator configuration:testLaunchConfiguration workingDirectory:workingDirectory reporter:reporter]
    connectAndStartWithError:error] != nil;
}

- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  FBTestManagerResult *result = [[FBSimulatorTestRunStrategy
    strategyWithSimulator:self.simulator configuration:nil workingDirectory:nil reporter:nil]
    waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:timeout];
  if (!result.didEndSuccessfully) {
    return [FBSimulatorError failBoolWithError:result.error errorOut:error];
  }
  return YES;
}

@end
