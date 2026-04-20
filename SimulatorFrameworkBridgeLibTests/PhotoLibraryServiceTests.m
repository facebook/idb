/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/PhotoLibraryService.h>

@interface PhotoLibraryServiceTests : XCTestCase
@end

@implementation PhotoLibraryServiceTests

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handlePhotoLibraryAction(@"delete"), 1);
  XCTAssertEqual(handlePhotoLibraryAction(@""), 1);
  XCTAssertEqual(handlePhotoLibraryAction(@"add"), 1);
}

@end
