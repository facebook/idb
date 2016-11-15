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

@interface FBXCTestRunner ()
@property (nonatomic, strong) FBXCTestConfiguration *configuration;
@end

@implementation FBXCTestRunner

+ (instancetype)testRunnerWithConfiguration:(FBXCTestConfiguration *)configuration
{
  FBXCTestRunner *runner = [self new];
  runner->_configuration = configuration;
  return runner;
}

- (BOOL)executeTestsWithError:(NSError **)error
{
  if (self.configuration.runWithoutSimulator) {
    if (self.configuration.runnerAppPath != nil) {
      return [[FBXCTestError describe:@"Application tests are not supported on OS X."] failBool:error];
    }

    if (self.configuration.listTestsOnly) {
      if (![[FBListTestRunner runnerWithConfiguration:self.configuration] listTestsWithError:error]) {
        return NO;
      }

      if (![self.configuration.reporter printReportWithError:error]) {
        return NO;
      }

      return YES;
    }

    if (![[FBLogicTestRunner withSimulator:nil configuration:self.configuration] runTestsWithError:error]) {
      return NO;
    }

    if (![self.configuration.reporter printReportWithError:error]) {
      return NO;
    }

    return YES;
  }

  if (self.configuration.listTestsOnly) {
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

  if (![self.configuration.reporter printReportWithError:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)runTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (self.configuration.runnerAppPath == nil) {
    return [[FBLogicTestRunner withSimulator:simulator configuration:self.configuration] runTestsWithError:error];
  }

  if (self.configuration.testFilter != nil) {
    return [[FBXCTestError describe:@"Test filtering is only supported for logic tests."] failBool:error];
  }

  return [[FBApplicationTestRunner withSimulator:simulator configuration:self.configuration] runTestsWithError:error];
}

@end
