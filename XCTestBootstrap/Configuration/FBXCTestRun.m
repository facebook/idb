/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRun.h"

#import "FBTestLaunchConfiguration.h"
#import "FBXCTestRunTarget.h"
#import "XCTestBootstrapError.h"

#import <DVTFoundation/DVTFilePath.h>
#import <IDEFoundation/IDETestRunSpecification.h>
#import <IDEFoundation/IDERunnable.h>

#import <objc/runtime.h>

@interface FBXCTestRun ()

@property (nonatomic, copy) NSArray<FBXCTestRunTarget *> *targets;
@property (nonatomic, copy) NSString *testRunFilePath;

@end

@implementation FBXCTestRun

+ (instancetype)withTestRunFileAtPath:(NSString *)testRunFilePath
{
  return [[self alloc] initWithTestRunFilePath:testRunFilePath];
}

- (instancetype)initWithTestRunFilePath:(NSString *)testRunFilePath
{
  NSParameterAssert(testRunFilePath);

  self = [super init];
  if (!self) {
    return nil;
  }

  _targets = @[];
  _testRunFilePath = [testRunFilePath copy];

  return self;
}

- (instancetype)buildWithError:(NSError **)error;
{
  NSError *innerError;

  // TODO: <plu> We need to make sure that the frameworks are loaded here already.
  DVTFilePath *path = [objc_lookUpClass("DVTFilePath") filePathForPathString:self.testRunFilePath];

  NSDictionary<NSString *, IDETestRunSpecification *> *testRunSpecifications = [objc_lookUpClass("IDETestRunSpecification")
    testRunSpecificationsAtFilePath:path
    workspace:nil
    error:&innerError];

  if (innerError) {
    return [[[XCTestBootstrapError describe:@"Failed to load xctestrun file"]
      causedBy:innerError]
      fail:error];
  }

  NSMutableArray<FBXCTestRunTarget *> *targets = [NSMutableArray array];
  NSArray<NSString *> *testTargetNames = [testRunSpecifications.allKeys sortedArrayUsingSelector:@selector(compare:)];

  for (NSString *testTargetName in testTargetNames) {
    IDETestRunSpecification *testRunSpecification = testRunSpecifications[testTargetName];

    if (!testRunSpecification.testBundleFilePath.pathString) {
      return [[XCTestBootstrapError describe:@"Could not find TestBundlePath in xctestrun file"] fail:error];
    }

    // TODO: <plu> To avoid valueForKeyPath here we should probably also dump IDEPathRunnable and everything that gets pulled by it.
    NSString *testHostPath = [testRunSpecification.testHostRunnable valueForKeyPath:@"filePath.pathString"];

    FBApplicationDescriptor *application = [FBApplicationDescriptor
      applicationWithPath:testHostPath
      error:&innerError];
    NSMutableArray *applications = [NSMutableArray arrayWithObject:application];

    if (innerError) {
      return [[[XCTestBootstrapError describe:@"Failed to find test host application"]
         causedBy:innerError]
        fail:error];
    }

    NSArray *commandLineArguments = testRunSpecification.commandLineArguments ?: @[];
    NSDictionary *environment = testRunSpecification.environmentVariables ?: @{};

    FBApplicationLaunchConfiguration *applicationLaunchConfiguration = [FBApplicationLaunchConfiguration
      configurationWithApplication:application
      arguments:commandLineArguments
      environment:environment
      options:0];

    NSSet *testsToSkip = testRunSpecification.testIdentifiersToSkip ?: [NSSet set];
    NSSet *testsToRun = testRunSpecification.testIdentifiersToRun ?: [NSSet set];

    FBTestLaunchConfiguration *testLaunchConfiguration = [[[[[[[FBTestLaunchConfiguration
      configurationWithTestBundlePath:testRunSpecification.testBundleFilePath.pathString]
      withApplicationLaunchConfiguration:applicationLaunchConfiguration]
      withTestsToSkip:testsToSkip]
      withTestsToRun:testsToRun]
      withUITesting:testRunSpecification.isUITestBundle]
      withTestHostPath:testHostPath]
      withTestEnvironment:testRunSpecification.testingEnvironmentVariables];

    if (testRunSpecification.isUITestBundle) {
      FBApplicationDescriptor *targetApplication = [FBApplicationDescriptor
        applicationWithPath:testRunSpecification.UITestingTargetAppPath
        error:&innerError];

      if (innerError) {
        return [[[XCTestBootstrapError describe:@"Failed to find test target application"]
          causedBy:innerError]
          fail:error];
      }

      NSString *targetApplicationBundleID = testRunSpecification.UITestingTargetAppBundleId ?: targetApplication.bundleID;

      testLaunchConfiguration = [[testLaunchConfiguration
        withTargetApplicationPath:testRunSpecification.UITestingTargetAppPath]
        withTargetApplicationBundleID:targetApplicationBundleID];

      [applications addObject:targetApplication];
    }

    FBXCTestRunTarget *target = [FBXCTestRunTarget
      withName:testTargetName
      testLaunchConfiguration:testLaunchConfiguration
      applications:applications];

    [targets addObject:target];
  }

  self.targets = targets.copy;

  return self;
}

@end
