/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlFixtures.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBSimulatorControlFixtures

+ (FBBundleDescriptor *)tableSearchApplicationWithError:(NSError **)error
{
  NSString *path = [[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"];
  return [FBBundleDescriptor bundleFromPath:path error:error];
}

+ (NSString *)photo0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"photo0" ofType:@"png"];
}

+ (NSString *)photo1Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"photo1" ofType:@"png"];
}

+ (NSString *)video0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"video0" ofType:@"mp4"];
}

+ (NSString *)simulatorSystemLogPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"simulator_system" ofType:@"log"];
}

+ (NSString *)treeJSONPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"tree" ofType:@"json"];
}

+ (NSString *)iOSUnitTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSUnitTestFixture" ofType:@"xctest"];
}

@end

@implementation XCTestCase (FBSimulatorControlFixtures)

- (FBTestLaunchConfiguration *)testLaunchTableSearch
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.iOSUnitTestBundlePath
    applicationLaunchConfiguration:self.tableSearchAppLaunch
    testHostPath:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationPath:nil
    targetApplicationBundleID:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coveragePath:nil
    logDirectoryPath:nil
    shims:nil];
}

- (FBTestLaunchConfiguration *)testLaunchSafari
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.iOSUnitTestBundlePath
    applicationLaunchConfiguration:self.safariAppLaunch
    testHostPath:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationPath:nil
    targetApplicationBundleID:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coveragePath:nil
    logDirectoryPath:nil
    shims:nil];
}

- (FBBundleDescriptor *)tableSearchApplication
{
  NSError *error = nil;
  FBBundleDescriptor *value = [FBSimulatorControlFixtures tableSearchApplicationWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);
  return value;
}

static NSString *const MobileSafariBundleName = @"MobileSafari";
static NSString *const MobileSafariBundleIdentifier = @"com.apple.mobilesafari";

- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch
{
  FBBundleDescriptor *application = self.tableSearchApplication;
  if (!application) {
    return nil;
  }
  return [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:application.identifier
    bundleName:application.name
    arguments:@[]
    environment:@{@"FROM" : @"FBSIMULATORCONTROL"}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunch
{
  return [self safariAppLaunchWithMode:FBApplicationLaunchModeFailIfRunning];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunchWithMode:(FBApplicationLaunchMode)launchMode
{
  return [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:MobileSafariBundleIdentifier
    bundleName:MobileSafariBundleName
    arguments:@[]
    environment:@{@"FROM" : @"FBSIMULATORCONTROL"}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:launchMode];
}

- (FBAgentLaunchConfiguration *)agentLaunch1
{
  return [[FBAgentLaunchConfiguration alloc]
    initWithLaunchPath:[FBBinaryDescriptor binaryWithPath:NSProcessInfo.processInfo.arguments[0] error:nil].path
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    output:FBProcessOutputConfiguration.outputToDevNull
    mode:FBAgentLaunchModeDefault];
}

- (nullable NSString *)iOSUnitTestBundlePath
{
  NSString *bundlePath = FBSimulatorControlFixtures.iOSUnitTestBundlePath;
  FBCodesignProvider *codesign = [FBCodesignProvider codeSignCommandWithAdHocIdentityWithLogger:nil];
  if ([[codesign cdHashForBundleAtPath:bundlePath] await:nil]) {
    return bundlePath;
  }
  NSError *error = nil;
  if ([[codesign signBundleAtPath:bundlePath] await:&error]) {
    return bundlePath;
  }
  XCTFail(@"Bundle at path %@ could not be codesigned: %@", bundlePath, error);
  return nil;
}

@end
