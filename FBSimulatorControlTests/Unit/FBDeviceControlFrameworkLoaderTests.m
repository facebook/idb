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

@interface FBDeviceControlFrameworkLoader ()

+ (BOOL)macOSVersionIsAtLeastSierra:(NSOperatingSystemVersion)macOSVersion;
+ (BOOL)xcodeVersionIsAtLeast81:(NSDecimalNumber *)xcodeVersion;
+ (NSArray<FBWeakFramework *> *)privateFrameworks;
+ (NSArray<FBWeakFramework *> *)privateFrameworkForMacOSVersion:(NSOperatingSystemVersion)macOSVersion
                                                   xcodeVersion:(NSDecimalNumber *)xcodeVersion;
@end

@interface FBDeviceControlFrameworkLoaderTests : XCTestCase

@end

@implementation FBDeviceControlFrameworkLoaderTests

- (void)testMacOSVersionAtLeastSierra
{
  NSOperatingSystemVersion elCap = {10, 11, 0};

  XCTAssertFalse([FBDeviceControlFrameworkLoader macOSVersionIsAtLeastSierra:elCap],
                 @"Expected 10.11.0 not to be at least Sierra");

  NSOperatingSystemVersion sierra = {10, 12, 0};
  XCTAssertTrue([FBDeviceControlFrameworkLoader macOSVersionIsAtLeastSierra:sierra],
                @"Expected 10.12.0 to be at least Sierra");

  NSOperatingSystemVersion nextOS = {10, 13, 0};
  XCTAssertTrue([FBDeviceControlFrameworkLoader macOSVersionIsAtLeastSierra:nextOS],
                @"Expected 10.13.0 to be at least Sierra");
};

- (void)testXcodeVersionIsAtLeast81
{
  NSDecimalNumber *version;

  version = [NSDecimalNumber decimalNumberWithString:@"7.3.1"];
  XCTAssertFalse([FBDeviceControlFrameworkLoader xcodeVersionIsAtLeast81:version],
                 @"Expect Xcode 7.3.1 not to be at least 8.1");

  version = [NSDecimalNumber decimalNumberWithString:@"8.0"];
  XCTAssertFalse([FBDeviceControlFrameworkLoader xcodeVersionIsAtLeast81:version],
                 @"Expect Xcode 8.0 not to be at least 8.1");

  version = [NSDecimalNumber decimalNumberWithString:@"8.1"];
  XCTAssertTrue([FBDeviceControlFrameworkLoader xcodeVersionIsAtLeast81:version],
                @"Expect Xcode 8.1 be at least 8.1");

  version = [NSDecimalNumber decimalNumberWithString:@"9.0"];
  XCTAssertTrue([FBDeviceControlFrameworkLoader xcodeVersionIsAtLeast81:version],
                @"Expect Xcode 9.0 be at least 8.1");
}

- (void)testPrivateFrameworks
{
  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  XCTAssertTrue(frameworks.count >= 7,
                @"Expected at least 7 frameworks, regardless of macOS and Xcode Version");
}

- (void)testPrivateFrameworksElCap
{
  NSOperatingSystemVersion elCap = {10, 11, 0};
  NSDecimalNumber *xcodeVersion;
  NSArray<FBWeakFramework *> *frameworks;

  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"7.3.1"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:elCap
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 7,
                @"Expected exactly 7 frameworks for ElCap for any Xcode version");

  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"8.2"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:elCap
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 7,
                @"Expected exactly 7 frameworks for ElCap for any Xcode version");

  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"10.0"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:elCap
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 7,
                @"Expected exactly 7 frameworks for ElCap for any Xcode version");
};

- (void)testPrivateFrameworkSierraXcodeLT80
{
  NSOperatingSystemVersion sierra = {10, 12, 0};
  NSDecimalNumber *xcodeVersion;
  NSArray<FBWeakFramework *> *frameworks;

  // Xcode 8.0 is lowest supported Xcode on Sierra
  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"8.0"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:sierra
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 7,
                @"Expected exactly 7 frameworks for Sierra for Xcode < 8.1");
}

- (void)testPrivateFrameworkSierraXcodeGTE81
{
  NSOperatingSystemVersion sierra = {10, 12, 0};
  NSDecimalNumber *xcodeVersion;
  NSArray<FBWeakFramework *> *frameworks;

  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"8.1"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:sierra
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 9,
                @"Expected exactly 9 frameworks for Sierra for Xcode >= 8.1");


  // It is likely that the Xcode 9 will be the last support Xcode on Sierra
  xcodeVersion = [NSDecimalNumber decimalNumberWithString:@"9.0"];
  frameworks = [FBDeviceControlFrameworkLoader privateFrameworkForMacOSVersion:sierra
                                                                  xcodeVersion:xcodeVersion];

  XCTAssertTrue(frameworks.count == 9,
                @"Expected exactly 9 frameworks for Sierra for Xcode >= 8.1");
}

@end
