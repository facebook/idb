/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRunStrategy.h"

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestManager.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "XCTestBootstrapError.h"

@interface FBXCTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBDeviceOperator> deviceOperator;
@property (nonatomic, strong, readonly) id<FBXCTestPreparationStrategy> prepareStrategy;
@property (nonatomic, strong, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDeviceOperator:deviceOperator testPrepareStrategy:prepareStrategy reporter:reporter logger:logger];
}

- (instancetype)initWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceOperator = deviceOperator;
  _prepareStrategy = prepareStrategy;
  _reporter = reporter;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBTestManager *)startTestManagerWithAttributes:(NSArray *)attributes environment:(NSDictionary *)environment error:(NSError **)error
{
  NSAssert(self.deviceOperator, @"Device operator is needed to perform meaningful test");
  NSAssert(self.prepareStrategy, @"Test preparation strategy is needed to perform meaningful test");

  FBTestRunnerConfiguration *configuration = [self.prepareStrategy prepareTestWithDeviceOperator:self.deviceOperator error:error];
  if (!configuration) {
    return nil;
  }

  if (![self.deviceOperator launchApplicationWithBundleID:configuration.testRunner.bundleID
                                                arguments:[self argumentsFromConfiguration:configuration attributes:attributes]
                                              environment:[self environmentFromConfiguration:configuration environment:environment]
                                                    error:error]) {
    return nil;
  }

  pid_t testRunnerProcessID = [self.deviceOperator processIDWithBundleID:configuration.testRunner.bundleID error:error];
  if (testRunnerProcessID <= 0) {
    return [[XCTestBootstrapError
      describe:@"Failed to determine launched process PID"]
      fail:error];
  }

  // Attach to the XCTest Test Runner host Process.
  FBTestManager *testManager = [FBTestManager testManagerWithOperator:self.deviceOperator
    testRunnerPID:testRunnerProcessID
    sessionIdentifier:configuration.sessionIdentifier
    reporter:self.reporter
    logger:self.logger];

  if (![testManager connectWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout error:error]) {
    return nil;
  }
  return testManager;
}

#pragma mark Private

- (NSArray<NSString *> *)argumentsFromConfiguration:(FBTestRunnerConfiguration *)configuration attributes:(NSArray<NSString *> *)attributes
{
  return [(configuration.launchArguments ?: @[]) arrayByAddingObjectsFromArray:(attributes ?: @[])];
}

- (NSDictionary<NSString *, NSString *> *)environmentFromConfiguration:(FBTestRunnerConfiguration *)configuration environment:(NSDictionary<NSString *, NSString *> *)environment
{
  NSMutableDictionary<NSString *, NSString *> *mEnvironment = (configuration.launchEnvironment ?: @{}).mutableCopy;
  if (environment) {
    [mEnvironment addEntriesFromDictionary:environment];
  }
  return [mEnvironment copy];
}

@end
