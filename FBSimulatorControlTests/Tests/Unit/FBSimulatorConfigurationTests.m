/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  XCTAssertTrue([configuration.device.model containsString:@"iPhone"]);
  XCTAssertTrue([configuration.os.name containsString:@"iOS"]);
}

- (void)testiPhoneConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone7] withOSNamed:FBOSVersionNameiOS_10_0];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModeliPhone7);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testiPadConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPadPro] withOSNamed:FBOSVersionNameiOS_10_0];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModeliPadPro);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testWatchOSConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleWatchSeries2_42mm] withOSNamed:FBOSVersionNamewatchOS_3_2];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModelAppleWatchSeries2_42mm);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNamewatchOS_3_2);
}

- (void)testTVOSConfiguration
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleTV] withOSNamed:FBOSVersionNametvOS_10_0];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModelAppleTV);
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNametvOS_10_0);
}

- (void)testAdjustsOSOfIncompatableProductFamily
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withOSNamed:FBOSVersionNametvOS_10_0] withDeviceModel:FBDeviceModeliPhone6];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModeliPhone6);
  XCTAssertTrue([configuration.os.name containsString:@"iOS"]);
}

- (void)testUsesCurrentOSIfUnknownDeviceAppears
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withOSNamed:FBOSVersionNameiOS_10_0] withDeviceModel:@"FooPad"];
  XCTAssertEqualObjects(configuration.device.model, @"FooPad");
  XCTAssertEqualObjects(configuration.os.name, FBOSVersionNameiOS_10_0);
}

- (void)testUsesCurrentDeviceIfUnknownOSAppears
{
  FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone7] withOSNamed:@"FooOS"];
  XCTAssertEqualObjects(configuration.device.model, FBDeviceModeliPhone7);
  XCTAssertEqualObjects(configuration.os.name, @"FooOS");
}

@end
