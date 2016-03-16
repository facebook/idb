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

#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestManager.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "NSError+XCTestBootstrap.h"

@interface FBXCTestRunStrategy ()
@property (nonatomic, strong) id<FBDeviceOperator> deviceOperator;
@property (nonatomic, strong) id<FBXCTestPreparationStrategy> prepareStrategy;
@property (nonatomic, strong) id<FBControlCoreLogger> logger;
@end

@implementation FBXCTestRunStrategy

+ (instancetype)strategyWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy logger:(id<FBControlCoreLogger>)logger
{
  FBXCTestRunStrategy *strategy = [self.class new];
  strategy.prepareStrategy = prepareStrategy;
  strategy.deviceOperator = deviceOperator;
  strategy.logger = logger;
  return strategy;
}

- (FBTestManager *)startTestManagerWithAttributes:(NSArray *)attributes environment:(NSDictionary *)environment error:(NSError **)error
{
  NSAssert(self.deviceOperator, @"Device operator is needed to perform meaningful test");
  NSAssert(self.prepareStrategy, @"Test preparation strategy is needed to perform meaningful test");

  FBTestRunnerConfiguration *configuration = [self.prepareStrategy prepareTestWithDeviceOperator:self.deviceOperator error:error];
  if (!configuration) {
    return nil;
  }

  NSMutableArray *mAttributes = (configuration.launchArguments ?: @[]).mutableCopy;
  if (attributes) {
    [mAttributes addObjectsFromArray:attributes];
  }

  NSMutableDictionary *mEnvironment = (configuration.launchEnvironment ?: @{}).mutableCopy;
  if (environment) {
    [mEnvironment addEntriesFromDictionary:environment];
  }

  if (![self.deviceOperator launchApplicationWithBundleID:configuration.testRunner.bundleID
                                                arguments:mAttributes.copy
                                              environment:mEnvironment.copy
                                                    error:error]) {
    return nil;
  }

  // Get XCTStubApps process Id
  pid_t testRunnerProcessID = [self.deviceOperator processIDWithBundleID:configuration.testRunner.bundleID error:error];
  if (testRunnerProcessID <= 0) {
    if (error) {
      *error = [NSError XCTestBootstrapErrorWithDescription:@"Failed to determine launched process PID"];
    }
    return nil;
  }

  // Attach WDA
  FBTestManager *testManager =
  [FBTestManager testManagerWithOperator:self.deviceOperator
                           testRunnerPID:testRunnerProcessID
                       sessionIdentifier:configuration.sessionIdentifier
                                  logger:self.logger
   ];
  if (![testManager connectWithError:error]) {
    return nil;
  }
  return testManager;
}

@end
