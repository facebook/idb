/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlLinkerTests : XCTestCase

@end

@implementation FBDeviceControlLinkerTests

- (void)testTheTest {
    FBCodeSignCommand *codesigner = [FBCodeSignCommand codeSignCommandWithIdentityName:@"iPhone Developer: Karl Krukow (YTTN6Y2QS9)"];
    
    setenv("DEVELOPER_DIR", "/Users/chrisf/Xcodes/8b6/Xcode-beta.app/Contents/Developer", YES);
    
    FBDeviceTestPreparationStrategy *testPrepareStrategy =
    [FBDeviceTestPreparationStrategy strategyWithTestRunnerApplicationPath:@"/Users/chrisf/iOSDeviceManager/Distribution/dependencies/ipa/DeviceAgent-Runner.app"
                                                       applicationDataPath:@"/Users/chrisf/scratch/appData.xcappdata"
                                                            testBundlePath:@"/Users/chrisf/iOSDeviceManager/Distribution/dependencies/ipa/DeviceAgent-Runner.app/PlugIns/DeviceAgent.xctest"
                                                    pathToXcodePlatformDir:@"/Users/chrisf/Xcodes/8b6/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform"
                                                          workingDirectory:@"/Users/chrisf"];
    
    NSError *err;
    FBDevice *device = [[FBDeviceSet defaultSetWithLogger:nil
                                                    error:&err] deviceWithUDID:@"c5fec20a4a41c65ac9475154ea2276255e4a2029"];
    
    if (err) {
        NSLog(@"Error creating device operator: %@", err);
        return;
    }
    device.deviceOperator.codesignProvider = codesigner;
    
    FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy strategyWithDeviceOperator:device.deviceOperator
                                                                       testPrepareStrategy:testPrepareStrategy
                                                                                  reporter:nil
                                                                                    logger:nil];
    NSError *innerError = nil;
    [testRunStrategy startTestManagerWithAttributes:@[] environment:@{} error:&innerError];
    
    XCTAssertNil(innerError, @"%@", innerError);
    if (!innerError) {
        [[NSRunLoop mainRunLoop] run];
    }
}

+ (void)initialize
{
  if (!NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging]) {
    setenv(FBControlCoreStderrLogging.UTF8String, "YES", 1);
  }
  if (!NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging]) {
    setenv(FBControlCoreDebugLogging.UTF8String, "NO", 1);
  }
}

- (void)testLinksPrivateFrameworks
{
  [FBDeviceControlFrameworkLoader initializeEssentialFrameworks];
  [FBDeviceControlFrameworkLoader initializeXCodeFrameworks];
}

- (void)testConstructsDeviceSet
{
  NSError *error = nil;
  FBDeviceSet *deviceSet = [FBDeviceSet defaultSetWithLogger:FBControlCoreGlobalConfiguration.defaultLogger error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(deviceSet);
  XCTAssertNotNil(deviceSet.allDevices);
}

- (void)testLazilyFetchesDVTClasses
{
  NSError *error = nil;
  FBDeviceSet *deviceSet = [FBDeviceSet defaultSetWithLogger:FBControlCoreGlobalConfiguration.defaultLogger error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil([deviceSet.allDevices valueForKey:@"description"]);
  XCTAssertEqual(deviceSet.allDevices.count, [[[deviceSet.allDevices valueForKey:@"deviceOperator"] filteredArrayUsingPredicate:NSPredicate.notNullPredicate] count]);
}

- (void)testReadsFromMobileDevice
{
  NSArray<FBAMDevice *> *devices = [FBAMDevice allDevices];
  XCTAssertNotNil(devices);
}

@end
