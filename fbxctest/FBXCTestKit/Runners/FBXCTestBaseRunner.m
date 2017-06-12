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
#import "FBLogicTestRunner.h"
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

- (BOOL)executeWithError:(NSError **)error
{
  BOOL success = [self.configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class] ? [self runiOSTestWithError:error] : [self runMacTestWithError:error];
  if (!success) {
    return NO;
  }
  if (![self.context.reporter printReportWithError:error]) {
    return NO;
  }
  return YES;
}

#pragma mark Private

- (BOOL)runMacTestWithError:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBApplicationTestConfiguration.class]) {
    return [[FBXCTestError describe:@"Application tests are not supported on OS X."] failBool:error];
  }
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[FBListTestStrategy macOSStrategyWithConfiguration:(FBListTestConfiguration *)self.configuration reporter:self.context.reporter] executeWithError:error];
  }
  return [[FBLogicTestRunner macOSRunnerWithConfiguration:(FBLogicTestConfiguration *)self.configuration context:self.context] executeWithError:error];
}

- (BOOL)runiOSTestWithError:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[FBXCTestError describe:@"Listing tests is only supported for macosx tests."] failBool:error];
  }
  FBSimulator *simulator = [self.context simulatorForiOSTestRun:self.configuration error:error];
  if (!simulator) {
    return NO;
  }

  BOOL testResult = [self runTestWithSimulator:simulator error:error];
  [self.context finishedExecutionOnSimulator:simulator];
  if (!testResult) {
    return NO;
  }

  return YES;
}

- (BOOL)runTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBLogicTestConfiguration.class]) {
    return [[FBLogicTestRunner iOSRunnerWithSimulator:simulator configuration:(FBLogicTestConfiguration *)self.configuration context:self.context] executeWithError:error];
  }
  return [[FBApplicationTestRunStrategy strategyWithSimulator:simulator configuration:(FBApplicationTestConfiguration *)self.configuration reporter:self.context.reporter logger:self.context.logger] executeWithError:error];
}

@end
