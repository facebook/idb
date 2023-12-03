/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
    initWithTestBundle:self.iOSUnitTestBundle
    applicationLaunchConfiguration:self.tableSearchAppLaunch
    testHostBundle:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationBundle:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coverageDirectoryPath:nil
    enableContinuousCoverageCollection:NO
    logDirectoryPath:nil
    reportResultBundle:NO];
}

- (FBTestLaunchConfiguration *)testLaunchSafari
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundle:self.iOSUnitTestBundle
    applicationLaunchConfiguration:self.safariAppLaunch
    testHostBundle:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationBundle:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coverageDirectoryPath:nil
    enableContinuousCoverageCollection:NO
    logDirectoryPath:nil
    reportResultBundle:NO];
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
    io:FBProcessIO.outputToDevNull
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
    io:FBProcessIO.outputToDevNull
    launchMode:launchMode];
}

- (FBProcessSpawnConfiguration *)agentLaunch1
{
  return [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:[FBBinaryDescriptor binaryWithPath:NSProcessInfo.processInfo.arguments[0] error:nil].path
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    io:FBProcessIO.outputToDevNull
    mode:FBProcessSpawnModeDefault];
}

- (nullable FBBundleDescriptor *)iOSUnitTestBundle
{
  NSError *error = nil;
  NSString *bundlePath = FBSimulatorControlFixtures.iOSUnitTestBundlePath;
  FBBundleDescriptor * bundle = [FBBundleDescriptor bundleFromPath:bundlePath error:&error];
  XCTAssert(bundle, @"Failed to load bundle at %@: %@", bundlePath, error);

  FBCodesignProvider *codesign = [FBCodesignProvider codeSignCommandWithAdHocIdentityWithLogger:nil];
  if ([[codesign cdHashForBundleAtPath:bundlePath] await:nil]) {
    return bundle;
  }
  if ([[codesign signBundleAtPath:bundlePath] await:&error]) {
    return bundle;
  }
  XCTFail(@"Bundle at path %@ could not be codesigned: %@", bundlePath, error);
  return nil;
}

@end
