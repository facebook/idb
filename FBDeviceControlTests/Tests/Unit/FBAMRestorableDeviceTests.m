/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMRestorableDevice.h>
#import <FBDeviceControl/FBDeviceCommands.h>

@interface FBAMRestorableDeviceTests : XCTestCase

@end

@implementation FBAMRestorableDeviceTests

- (FBAMRestorableDevice *)deviceWithAllValues:(NSDictionary<NSString *, id> *)allValues
{
  AMDCalls calls = {};
  return [[FBAMRestorableDevice alloc]
          initWithCalls:calls
          restorableDevice:(__bridge AMRestorableDeviceRef) @"fake-restorable-ref"
          allValues:allValues
          workQueue:dispatch_queue_create("com.facebook.fbdevicecontrol.tests.work", DISPATCH_QUEUE_SERIAL)
          asyncQueue:dispatch_queue_create("com.facebook.fbdevicecontrol.tests.async", DISPATCH_QUEUE_SERIAL)
          logger:FBControlCoreGlobalConfiguration.defaultLogger];
}

- (void)testStringProductTypeFlowsIntoDeviceType
{
  FBAMRestorableDevice *device = [self deviceWithAllValues:@{FBDeviceKeyProductType : @"iPhone14,2"}];
  XCTAssertEqualObjects(device.deviceType.model, @"iPhone14,2");
}

- (void)testStringDeviceNameFlowsIntoName
{
  FBAMRestorableDevice *device = [self deviceWithAllValues:@{FBDeviceKeyDeviceName : @"lab-device"}];
  XCTAssertEqualObjects(device.name, @"lab-device");
}

- (void)testNumericUniqueChipIDFlowsIntoUniqueIdentifier
{
  FBAMRestorableDevice *device = [self deviceWithAllValues:@{FBDeviceKeyUniqueChipID : @12345}];
  XCTAssertEqualObjects(device.uniqueIdentifier, @"12345");
}

- (void)testMissingDeviceNameFallsBackToUnknown
{
  FBAMRestorableDevice *device = [self deviceWithAllValues:@{}];
  XCTAssertEqualObjects(device.name, @"unknown");
}

- (void)testMissingUniqueChipIDFallsBackToUnknown
{
  FBAMRestorableDevice *device = [self deviceWithAllValues:@{}];
  XCTAssertEqualObjects(device.uniqueIdentifier, @"unknown");
}

@end
