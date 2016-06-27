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

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlLinkerTests : XCTestCase

@end

@implementation FBDeviceControlLinkerTests

- (void)testTheTest {
    FBCodeSignCommand *codesigner = [FBCodeSignCommand codeSignCommandWithIdentityName:@"iPhone Developer: Chris Fuentes (G7R46E5NX7)"];
    
    FBDeviceTestPreparationStrategy *testPrepareStrategy =
    [FBDeviceTestPreparationStrategy strategyWithTestRunnerApplicationPath:@"/Users/chrisf/calabash-xcuitest-server/Products/ipa/DeviceAgent/CBX-Runner.app"
                                                       applicationDataPath:@"/Users/chrisf/scratch/appData.xcappdata"
                                                            testBundlePath:@"/Users/chrisf/calabash-xcuitest-server/Products/ipa/DeviceAgent/CBX-Runner.app/PlugIns/CBX.xctest"
                                                    pathToXcodePlatformDir:@"/Applications/Xcode.app/Contents/Developer"
                                                          workingDirectory:@"/Users/chrisf"];
    
    NSError *err;
    FBiOSDeviceOperator *op = [FBiOSDeviceOperator operatorWithDeviceUDID:@"49a29c9e61998623e7909e35e8bae50dd07ef85f"
                                                         codesignProvider:codesigner
                                                                    error:&err];
    
    if (err) {
        NSLog(@"Error creating device operator: %@", err);
        return;
    }
    FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy strategyWithDeviceOperator:op
                                                                       testPrepareStrategy:testPrepareStrategy
                                                                                  reporter:nil
                                                                                    logger:nil];
    NSError *innerError = nil;
    [testRunStrategy startTestManagerWithAttributes:@[] environment:@{} error:&innerError];
    
    if (!innerError) {
        [[NSRunLoop mainRunLoop] run];
    } else {
        NSLog(@"Err: %@", innerError);
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
