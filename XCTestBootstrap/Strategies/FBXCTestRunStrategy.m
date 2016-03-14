// Copyright 2004-present Facebook. All Rights Reserved.

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
@end

@implementation FBXCTestRunStrategy

+ (instancetype)strategyWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy
{
  FBXCTestRunStrategy *strategy = [self.class new];
  strategy.prepareStrategy = prepareStrategy;
  strategy.deviceOperator = deviceOperator;
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
   ];
  if (![testManager connectWithError:error]) {
    return nil;
  }
  return testManager;
}

@end
