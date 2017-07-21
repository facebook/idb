/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlFixtures.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBSimulatorControlFixtures

+ (FBApplicationBundle *)tableSearchApplicationWithError:(NSError **)error
{
  NSString *path = [[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"];
  return [FBApplicationBundle userApplicationWithPath:path error:error];
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

- (FBTestLaunchConfiguration *)testLaunch
{
  return [[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.iOSUnitTestBundlePath]
    withApplicationLaunchConfiguration:self.tableSearchAppLaunch]
    withUITesting:NO];
}

- (FBApplicationBundle *)tableSearchApplication
{
  NSError *error = nil;
  FBApplicationBundle *value = [FBSimulatorControlFixtures tableSearchApplicationWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);
  return value;
}

static NSString *const MobileSafariBundleName = @"MobileSafari";
static NSString *const MobileSafariBundleIdentifier = @"com.apple.mobilesafari";

- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch
{
  FBApplicationBundle *application = self.tableSearchApplication;
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
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:MobileSafariBundleIdentifier
    bundleName:MobileSafariBundleName
    arguments:@[]
    environment:@{@"FROM" : @"FBSIMULATORCONTROL"}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBAgentLaunchConfiguration *)agentLaunch1
{
  return [FBAgentLaunchConfiguration
    configurationWithBinary:[FBBinaryDescriptor binaryWithPath:NSProcessInfo.processInfo.arguments[0] error:nil]
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (nullable NSString *)iOSUnitTestBundlePath
{
  NSString *bundlePath = FBSimulatorControlFixtures.iOSUnitTestBundlePath;
  if (!FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return bundlePath;
  }
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  if ([codesign cdHashForBundleAtPath:bundlePath error:nil]) {
    return bundlePath;
  }
  NSError *error = nil;
  if ([codesign signBundleAtPath:bundlePath error:&error]) {
    return bundlePath;
  }
  XCTFail(@"Bundle at path %@ could not be codesigned: %@", bundlePath, error);
  return nil;
}

@end
