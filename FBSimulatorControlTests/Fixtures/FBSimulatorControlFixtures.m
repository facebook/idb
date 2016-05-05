/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlFixtures.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBSimulatorControlFixtures

+ (FBSimulatorApplication *)tableSearchApplicationWithError:(NSError **)error
{
  NSString *path = [[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"];
  return [FBSimulatorApplication applicationWithPath:path error:error];
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

+ (NSString *)applicationTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"SimpleTestTarget" ofType:@"xctest"];
}

@end

@implementation XCTestCase (FBSimulatorControlFixtures)

- (FBSimulatorApplication *)tableSearchApplication
{
  NSError *error = nil;
  FBSimulatorApplication *value = [FBSimulatorControlFixtures tableSearchApplicationWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);
  return value;
}

- (FBSimulatorApplication *)safariApplication
{
  NSError *error = nil;
  FBSimulatorApplication *application = [FBSimulatorApplication systemApplicationNamed:@"MobileSafari" error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(application, @"Could not fetch MobileSafari");
  return application;
}

- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch
{
  FBSimulatorApplication *application = self.tableSearchApplication;
  if (!application) {
    return nil;
  }
  return [FBApplicationLaunchConfiguration configurationWithApplication:application arguments:@[] environment:@{} options:0];
}

- (FBApplicationLaunchConfiguration *)safariAppLaunch
{
  FBSimulatorApplication *application = self.safariApplication;
  if (!application) {
    return nil;
  }
  return [FBApplicationLaunchConfiguration configurationWithApplication:application arguments:@[] environment:@{} options:0];
}

- (FBAgentLaunchConfiguration *)agentLaunch1
{
  return [FBAgentLaunchConfiguration
    configurationWithBinary:self.safariApplication.binary
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}
    options:0];
}

- (FBApplicationLaunchConfiguration *)appLaunch1
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:self.tableSearchApplication
    arguments:@[@"LAUNCH1"]
    environment:@{@"FOO" : @"BAR"}
    options:0];
}

- (FBApplicationLaunchConfiguration *)appLaunch2
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:self.safariApplication
    arguments:@[@"LAUNCH2"]
    environment:@{@"BING" : @"BONG"}
    options:0];
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

- (NSString *)applicationTestBundlePath
{
  return FBSimulatorControlFixtures.applicationTestBundlePath;
}

@end
