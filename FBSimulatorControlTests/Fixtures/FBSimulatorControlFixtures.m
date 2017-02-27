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

+ (FBApplicationDescriptor *)tableSearchApplicationWithError:(NSError **)error
{
  NSString *path = [[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"];
  return [FBApplicationDescriptor userApplicationWithPath:path error:error];
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

+ (NSString *)iOSUITestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSUITestFixture" ofType:@"xctest"];
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

- (FBTestLaunchConfiguration *)uiTestLaunch
{
  // Xcode embeds the XCTest.framework into the UI Test Runner application that is automatically being created when
  // building a UI Test target. To avoid committing big binaries to the repository there's no such Test Runner
  // Application included, instead Safari.app is being abused as the Test Runner. Safari.app does not contain the
  // embedded XCTest.framework. It will be loaded from Xcode's Platforms path to work around this.
  NSString *frameworkPath = [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks"];
  NSDictionary *environment = @{@"DYLD_FRAMEWORK_PATH": frameworkPath};
  return [[[[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:FBSimulatorControlFixtures.iOSUITestBundlePath]
    withApplicationLaunchConfiguration:[self.safariAppLaunch withEnvironment:environment]]
    withUITestingTargetApplicationPath:self.tableSearchApplication.path]
    withUITestingTargetApplicationBundleID:self.tableSearchApplication.bundleID]
    withUITesting:YES];
}

- (FBApplicationDescriptor *)tableSearchApplication
{
  NSError *error = nil;
  FBApplicationDescriptor *value = [FBSimulatorControlFixtures tableSearchApplicationWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);
  return value;
}

- (FBApplicationDescriptor *)safariApplication
{
  NSError *error = nil;
  FBApplicationDescriptor *application = [FBApplicationDescriptor systemApplicationNamed:@"MobileSafari" error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(application, @"Could not fetch MobileSafari");
  return application;
}

- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch
{
  FBApplicationDescriptor *application = self.tableSearchApplication;
  if (!application) {
    return nil;
  }
  return [FBApplicationLaunchConfiguration configurationWithApplication:application arguments:@[] environment:@{} output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunch
{
  FBApplicationDescriptor *application = self.safariApplication;
  if (!application) {
    return nil;
  }
  return [FBApplicationLaunchConfiguration configurationWithApplication:application arguments:@[] environment:@{} output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBAgentLaunchConfiguration *)agentLaunch1
{
  return [FBAgentLaunchConfiguration
    configurationWithBinary:self.safariApplication.binary
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBApplicationLaunchConfiguration *)appLaunch1
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:self.tableSearchApplication
    arguments:@[@"LAUNCH1"]
    environment:@{@"FOO" : @"BAR"}
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBApplicationLaunchConfiguration *)appLaunch2
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:self.safariApplication
    arguments:@[@"LAUNCH2"]
    environment:@{@"BING" : @"BONG"}
    output:FBProcessOutputConfiguration.outputToDevNull];
}

- (FBProcessInfo *)processInfo1
{
  return [[FBProcessInfo alloc]
    initWithProcessIdentifier:42
    launchPath:self.tableSearchApplication.binary.path
    arguments:self.appLaunch1.arguments
    environment:self.appLaunch1.environment];
}

- (FBProcessInfo *)processInfo2
{
  return [[FBProcessInfo alloc]
    initWithProcessIdentifier:20
    launchPath:self.safariApplication.binary.path
    arguments:self.appLaunch2.arguments
    environment:self.appLaunch2.environment];
}

- (FBProcessInfo *)processInfo2a
{
  return [[FBProcessInfo alloc]
    initWithProcessIdentifier:30
    launchPath:self.safariApplication.binary.path
    arguments:self.appLaunch2.arguments
    environment:self.appLaunch2.environment];
}

- (nullable NSString *)signBundleAtPath:(NSString *)bundlePath
{
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

- (nullable NSString *)iOSUnitTestBundlePath
{
  return [self signBundleAtPath:FBSimulatorControlFixtures.iOSUnitTestBundlePath];
}

- (nullable NSString *)iOSUITestBundlePath
{
  return [self signBundleAtPath:FBSimulatorControlFixtures.iOSUITestBundlePath];
}

@end
