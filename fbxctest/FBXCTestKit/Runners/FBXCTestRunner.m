/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRunner.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <sys/types.h>
#import <sys/stat.h>

#import "FBJSONTestReporter.h"
#import "FBXCTestConfiguration.h"
#import "FBXCTestError.h"
#import "FBXCTestReporterAdapter.h"
#import "FBXCTestLogger.h"
#import "FBApplicationTestRunner.h"
#import "FBXCTestSimulatorFetcher.h"
#import "FBLogicTestRunner.h"
#import "FBXCTestShimConfiguration.h"
#import "FBListTestRunner.h"
#import "FBXCTestDestination.h"

@interface FBXCTestRunner ()
@property (nonatomic, strong) FBXCTestConfiguration *configuration;
@end

@implementation FBXCTestRunner

+ (instancetype)testRunnerWithConfiguration:(FBXCTestConfiguration *)configuration
{
  return [[self alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  return self;
}

- (BOOL)executeTestsWithError:(NSError **)error
{
  BOOL success = [self.configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class] ? [self runiOSTestWithError:error] : [self runMacTestWithError:error];
  if (!success) {
    return NO;
  }
  if (![self.configuration.reporter printReportWithError:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)runMacTestWithError:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBApplicationTestConfiguration.class]) {
    return [[FBXCTestError describe:@"Application tests are not supported on OS X."] failBool:error];
  }
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[FBListTestRunner runnerWithConfiguration:self.configuration] listTestsWithError:error];
  }
  return [[FBLogicTestRunner withSimulator:nil configuration:(FBLogicTestConfiguration *)self.configuration] runTestsWithError:error];
}

- (BOOL)runiOSTestWithError:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBListTestConfiguration.class]) {
    return [[FBXCTestError describe:@"Listing tests is only supported for macosx tests."] failBool:error];
  }
  FBXCTestSimulatorFetcher *simulatorFetcher = [FBXCTestSimulatorFetcher withConfiguration:self.configuration error:error];
  if (!simulatorFetcher) {
    return NO;
  }
  FBSimulator *simulator = [simulatorFetcher fetchSimulatorForWithError:error];
  if (!simulator) {
    return NO;
  }

  BOOL testResult = [self runTestWithSimulator:simulator error:error];
  [simulatorFetcher returnSimulator:simulator error:nil];
  if (!testResult) {
    return NO;
  }

  return YES;
}

- (BOOL)runTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if ([self.configuration isKindOfClass:FBLogicTestConfiguration.class]) {
    return [[FBLogicTestRunner withSimulator:simulator configuration:(FBLogicTestConfiguration *)self.configuration] runTestsWithError:error];
  }
  return [[FBApplicationTestRunner withSimulator:simulator configuration:(FBApplicationTestConfiguration *)self.configuration] runTestsWithError:error];
}

@end
