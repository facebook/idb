/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

@interface FBSimulatorConfigurationTests : XCTestCase

@end

@implementation FBSimulatorConfigurationTests

- (void)testAllConfigurationsArePresent
{
  NSMutableArray<NSString *> *absentOSVersions = [NSMutableArray array];
  NSMutableArray<NSString *> *absentDeviceTypes = [NSMutableArray array];
  [FBSimulatorConfiguration allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:&absentOSVersions absentDeviceTypesOut:&absentDeviceTypes];
  XCTAssertEqualObjects(absentOSVersions, @[]);
  XCTAssertEqualObjects(absentDeviceTypes, @[]);
}

- (void)testDefaultIsIphone
{
  FBSimulatorConfiguration *configuration = FBSimulatorConfiguration.defaultConfiguration;
  XCTAssertTrue([configuration.device.deviceName containsString:@"iPhone"]);
  XCTAssertTrue([configuration.os.name containsString:@"iOS"]);
}

- (void)testiPhoneConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceNamed:FBDeviceNameiPhone7] withOSNamed:FBOSVersionNameiOS_10_0];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameiPhone7);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testiPadConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceNamed:FBDeviceNameiPadPro] withOSNamed:FBOSVersionNameiOS_10_0];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameiPadPro);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testWatchOSConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceNamed:FBDeviceNameAppleWatchSeries2_42mm] withOSNamed:FBOSVersionNamewatchOS_3_2];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameAppleWatchSeries2_42mm);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNamewatchOS_3_2);
}

- (void)testTVOSConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceNamed:FBDeviceNameAppleTV1080p] withOSNamed:FBOSVersionNametvOS_10_0];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameAppleTV1080p);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNametvOS_10_0);
}

- (void)testAdjustsOSOfIncompatableProductFamily
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withOSNamed:FBOSVersionNametvOS_10_0] withDeviceNamed:FBDeviceNameiPhone6];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameiPhone6);
  XCTAssertTrue([configuration.os.name containsString:@"iOS"]);
}

- (void)testUsesCurrentOSIfUnknownDeviceAppears
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withOSNamed:FBOSVersionNameiOS_10_0] withDeviceNamed:@"FooPad"];
  XCTAssertEqualObjects(configuration.device.deviceName, @"FooPad");
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testUsesCurrentDeviceIfUnknownOSAppears
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceNamed:FBDeviceNameiPhone7] withOSNamed:@"FooOS"];
  XCTAssertEqualObjects(configuration.device.deviceName, FBDeviceNameiPhone7);
  XCTAssertEqualObjects(configuration.os.name, @"FooOS");
}

@end
