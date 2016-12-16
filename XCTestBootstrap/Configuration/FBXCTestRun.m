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
#import "XCTestBootstrapFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <DVTFoundation/DVTFilePath.h>
#import <IDEFoundation/IDETestRunSpecification.h>
#import <IDEFoundation/IDEPathRunnable.h>
#import <IDEFoundation/IDERunnable.h>

#import <objc/runtime.h>

@interface FBXCTestRun ()

@property (nonatomic, copy) NSArray<FBXCTestRunTarget *> *targets;
@property (nonatomic, copy) NSString *testRunFilePath;

@end

@implementation FBXCTestRun

+ (void)initialize
{
  [XCTestBootstrapFrameworkLoader loadPrivateFrameworksOrAbort];
}

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
  if (!FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return [[XCTestBootstrapError describe:@"Loading xctestrun files is only supported with Xcode 8 or later"] fail:error];
  }

  NSError *innerError;

  DVTFilePath *path = [objc_lookUpClass("DVTFilePath") filePathForPathString:self.testRunFilePath];

  NSDictionary<NSString *, IDETestRunSpecification *> *testRunSpecifications = [objc_lookUpClass("IDETestRunSpecification")
    testRunSpecificationsAtFilePath:path
    workspace:nil
    error:&innerError];

  if (innerError || testRunSpecifications.count == 0) {
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

    FBApplicationDescriptor *application = [FBApplicationDescriptor
      userApplicationWithPath:[self testHostPathFromTestRunSpecification:testRunSpecification]
      error:&innerError];

    if (innerError) {
      return [[[XCTestBootstrapError describe:@"Failed to find test host application"]
        causedBy:innerError]
        fail:error];
    }

    NSMutableArray *applications = [NSMutableArray arrayWithObject:application];

    FBTestLaunchConfiguration *testLaunchConfiguration = [self
      testLaunchConfigurationWithTestRunSpecification:testRunSpecification
      application:application];

    if (testRunSpecification.isUITestBundle) {
      FBApplicationDescriptor *targetApplication = [FBApplicationDescriptor
        userApplicationWithPath:testRunSpecification.UITestingTargetAppPath
        error:&innerError];

      if (innerError) {
        return [[[XCTestBootstrapError describe:@"Failed to find test target application"]
          causedBy:innerError]
          fail:error];
      }

      [applications addObject:targetApplication];

      NSString *targetApplicationBundleID = testRunSpecification.UITestingTargetAppBundleId ?: targetApplication.bundleID;

      testLaunchConfiguration = [[testLaunchConfiguration
        withTargetApplicationPath:testRunSpecification.UITestingTargetAppPath]
        withTargetApplicationBundleID:targetApplicationBundleID];
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

#pragma mark - Private

- (FBTestLaunchConfiguration *)testLaunchConfigurationWithTestRunSpecification:(IDETestRunSpecification *)testRunSpecification application:(FBApplicationDescriptor *)application
{
  NSSet *testsToSkip = testRunSpecification.testIdentifiersToSkip ?: [NSSet set];
  NSSet *testsToRun = testRunSpecification.testIdentifiersToRun ?: [NSSet set];

  NSArray *commandLineArguments = testRunSpecification.commandLineArguments ?: @[];
  NSDictionary *environment = testRunSpecification.environmentVariables ?: @{};

  FBApplicationLaunchConfiguration *applicationLaunchConfiguration = [FBApplicationLaunchConfiguration
    configurationWithApplication:application
    arguments:commandLineArguments
    environment:environment
    output:FBProcessOutputConfiguration.defaultOutputToFile];

  return [[[[[[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:testRunSpecification.testBundleFilePath.pathString]
    withApplicationLaunchConfiguration:applicationLaunchConfiguration]
    withTestsToSkip:testsToSkip]
    withTestsToRun:testsToRun]
    withUITesting:testRunSpecification.isUITestBundle]
    withTestHostPath:[self testHostPathFromTestRunSpecification:testRunSpecification]]
    withTestEnvironment:testRunSpecification.testingEnvironmentVariables];
}

- (NSString *)testHostPathFromTestRunSpecification:(IDETestRunSpecification *)testRunSpecification
{
  NSAssert([testRunSpecification.testHostRunnable isKindOfClass:objc_lookUpClass("IDEPathRunnable")],
           @"Invalid class, expected testHostRunnable to be of type: IDEPathRunnable");
  return ((IDEPathRunnable *)testRunSpecification.testHostRunnable).filePath.pathString;
}

@end
