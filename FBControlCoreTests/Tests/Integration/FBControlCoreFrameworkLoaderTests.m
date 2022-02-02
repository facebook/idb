/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBControlCoreFrameworkLoaderTests : XCTestCase

@end

@implementation FBControlCoreFrameworkLoaderTests

- (void)assertLoadsFramework:(FBWeakFramework *)framework
{
  NSError *error = nil;
  BOOL success = [framework loadWithLogger:FBControlCoreGlobalConfiguration.defaultLogger error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testLoadsAccessibilityPlatformTranslation
{
  [self assertLoadsFramework:FBWeakFramework.AccessibilityPlatformTranslation];
}

- (void)testLoadsCoreSimulator
{
  [self assertLoadsFramework:FBWeakFramework.CoreSimulator];
}

- (void)testLoadsDTXConnectionServices
{
  [self assertLoadsFramework:FBWeakFramework.DTXConnectionServices];
}

- (void)testLoadsMobileDevice
{
  [self assertLoadsFramework:FBWeakFramework.MobileDevice];
}

- (void)testLoadsSimulatorKit
{
  [self assertLoadsFramework:FBWeakFramework.SimulatorKit];
}

- (void)testLoadsXCTest
{
  [self assertLoadsFramework:FBWeakFramework.XCTest];
}

@end
