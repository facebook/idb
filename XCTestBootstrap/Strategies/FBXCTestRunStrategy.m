// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestRunStrategy.h"

#import <Foundation/Foundation.h>

#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "NSError+XCTestBootstrap.h"

@interface FBXCTestRunStrategy () <FBTestManagerDelegate>
@property (nonatomic, strong) id<FBDeviceOperator> deviceOperator;
@property (nonatomic, strong) id<FBXCTestPreparationStrategy> prepareStrategy;
@property (nonatomic, strong) FBTestManagerAPIMediator *mediator;
@end

@implementation FBXCTestRunStrategy

+ (instancetype)strategyWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy
{
  FBXCTestRunStrategy *strategy = [self.class new];
  strategy.prepareStrategy = prepareStrategy;
  strategy.deviceOperator = deviceOperator;
  return strategy;
}

- (BOOL)startTestWithAttributes:(NSArray *)attributes environment:(NSDictionary *)environment error:(NSError **)error
{
  NSAssert(self.deviceOperator, @"Device operator is needed to perform meaningful test");
  NSAssert(self.prepareStrategy, @"Test preparation strategy is needed to perform meaningful test");

  FBTestRunnerConfiguration *configuration = [self.prepareStrategy prepareTestWithDeviceOperator:self.deviceOperator error:error];
  if (!configuration) {
    return NO;
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
    return NO;
  }

  // Get XCTStubApps process Id
  pid_t testRunnerProcessID = [self.deviceOperator processIDWithBundleID:configuration.testRunner.bundleID error:error];
  if (testRunnerProcessID <= 0) {
    if (error) {
      *error = [NSError XCTestBootstrapErrorWithDescription:@"Failed to determine launched process PID"];
    }
    return NO;
  }

  // Attach WDA
  self.mediator =
  [FBTestManagerAPIMediator mediatorWithDevice:self.deviceOperator.dvtDevice
                                 testRunnerPID:testRunnerProcessID
                             sessionIdentifier:configuration.sessionIdentifier];
  self.mediator.delegate = self;
  [self.mediator connectTestRunnerWithTestManagerDaemon];
  return YES;
}


#pragma mark - FBTestManagerDelegate

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment error:(NSError **)error
{
  if (![self.deviceOperator installApplicationWithPath:path error:error]) {
    return NO;
  }
  if (![self.deviceOperator launchApplicationWithBundleID:bundleID arguments:arguments environment:environment error:error]) {
    return NO;
  }
  return YES;
}

@end
