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

+ (NSString *)JUnitXMLResult0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"junitResult0" ofType:@"xml"];
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
  return [[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.iOSUnitTestBundlePath]
    withApplicationLaunchConfiguration:self.tableSearchAppLaunch]
    withUITesting:NO];
}

- (FBTestLaunchConfiguration *)testLaunchSafari
{
  return [[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.iOSUnitTestBundlePath]
    withApplicationLaunchConfiguration:self.safariAppLaunch]
    withUITesting:NO];
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
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:application
    arguments:@[]
    environment:@{@"FROM" : @"FBSIMULATORCONTROL"}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunch
{
  return [self safariAppLaunchWithMode:FBApplicationLaunchModeFailIfRunning];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunchWithMode:(FBApplicationLaunchMode)launchMode
{
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:MobileSafariBundleIdentifier
    bundleName:MobileSafariBundleName
    arguments:@[]
    environment:@{@"FROM" : @"FBSIMULATORCONTROL"}
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:launchMode];
}

- (FBAgentLaunchConfiguration *)agentLaunch1
{
  return [FBAgentLaunchConfiguration
    configurationWithBinary:[FBBinaryDescriptor binaryWithPath:NSProcessInfo.processInfo.arguments[0] error:nil]
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    output:FBProcessOutputConfiguration.outputToDevNull
    mode:FBAgentLaunchModeDefault];
}

- (nullable NSString *)iOSUnitTestBundlePath
{
  NSString *bundlePath = FBSimulatorControlFixtures.iOSUnitTestBundlePath;
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
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
