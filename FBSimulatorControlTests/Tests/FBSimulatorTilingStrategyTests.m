/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorWindowTilingStrategy.h>

@interface FBSimulatorTilingStrategyTests : XCTestCase

@end

@implementation FBSimulatorTilingStrategyTests

- (void)testTilesInRegions
{
  CGRect window = [[FBSimulatorWindowTilingStrategy isolatedRegionStrategyWithOffset:0 total:3]
    targetPositionOfWindowWithSize:CGSizeMake(100, 200) inScreenSize:CGSizeMake(1024, 768) withError:nil];
  XCTAssertTrue(CGRectEqualToRect(CGRectMake(0, 0, 100, 200), window));

  window = [[FBSimulatorWindowTilingStrategy isolatedRegionStrategyWithOffset:1 total:3]
    targetPositionOfWindowWithSize:CGSizeMake(300, 200) inScreenSize:CGSizeMake(1024, 768) withError:nil];
  XCTAssertTrue(CGRectEqualToRect(CGRectMake(341, 0, 300, 200), window));

  window = [[FBSimulatorWindowTilingStrategy isolatedRegionStrategyWithOffset:2 total:3]
    targetPositionOfWindowWithSize:CGSizeMake(200, 500) inScreenSize:CGSizeMake(1024, 768) withError:nil];
  XCTAssertTrue(CGRectEqualToRect(CGRectMake(682, 0, 200, 500), window));
}

@end
