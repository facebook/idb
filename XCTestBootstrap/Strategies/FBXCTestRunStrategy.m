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
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"
#import "FBProductBundle.h"
#import "FBTestManager.h"
#import "FBTestManagerContext.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "XCTestBootstrapError.h"

@interface FBXCTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> iosTarget;
@property (nonatomic, strong, readonly) id<FBXCTestPreparationStrategy> prepareStrategy;
@property (nonatomic, strong, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithIOSTarget:(id<FBiOSTarget>)iosTarget testPrepareStrategy:(id<FBXCTestPreparationStrategy>)testPrepareStrategy reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithIOSTarget:iosTarget testPrepareStrategy:testPrepareStrategy reporter:reporter logger:logger];
}

- (instancetype)initWithIOSTarget:(id<FBiOSTarget>)iosTarget testPrepareStrategy:(id<FBXCTestPreparationStrategy>)prepareStrategy reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _iosTarget = iosTarget;
  _prepareStrategy = prepareStrategy;
  _reporter = reporter;
  _logger = [logger withPrefix:[NSString stringWithFormat:@"%@:", iosTarget.udid]];

  return self;
}

#pragma mark Public

- (nullable FBTestManager *)startTestManagerWithAttributes:(NSArray<NSString *> *)attributes environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error
{
  NSAssert(self.iosTarget, @"iOS Target is needed to perform meaningful test");
  NSAssert(self.prepareStrategy, @"Test preparation strategy is needed to perform meaningful test");
  NSError *innerError;
  FBTestRunnerConfiguration *configuration = [self.prepareStrategy prepareTestWithIOSTarget:self.iosTarget error:&innerError];
  if (!configuration) {
    return [[[XCTestBootstrapError
      describe:@"Failed to prepare test runner configuration"]
      causedBy:innerError]
      fail:error];
  }

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:configuration.testRunner.bundleID
    bundleName:configuration.testRunner.bundleID
    arguments:[self argumentsFromConfiguration:configuration attributes:attributes]
    environment:[self environmentFromConfiguration:configuration environment:environment]
    output:FBProcessOutputConfiguration.outputToDevNull];

  if (![self.iosTarget launchApplication:appLaunch error:&innerError]) {
    return [[[XCTestBootstrapError describe:@"Failed launch test runner"]
      causedBy:innerError]
      fail:error];
  }

  pid_t testRunnerProcessID = [self.iosTarget.deviceOperator processIDWithBundleID:configuration.testRunner.bundleID error:error];
  if (testRunnerProcessID < 1) {
    return [[XCTestBootstrapError
      describe:@"Failed to determine test runner process PID"]
      fail:error];
  }

  // Make the Context for the Test Manager.
  FBTestManagerContext *context = [FBTestManagerContext
    contextWithTestRunnerPID:testRunnerProcessID
    testRunnerBundleID:configuration.testRunner.bundleID
    sessionIdentifier:configuration.sessionIdentifier];

  // Attach to the XCTest Test Runner host Process.
  FBTestManager *testManager = [FBTestManager
    testManagerWithContext:context
    iosTarget:self.iosTarget
    reporter:self.reporter
    logger:self.logger];

  FBTestManagerResult *result = [testManager connectWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];
  if (result) {
    return[[[XCTestBootstrapError
      describeFormat:@"Test Manager Connection Failed: %@", result.description]
      causedBy:result.error]
      fail:error];
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
