/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBXcodeDirectoryTests : XCTestCase

@end

@implementation FBXcodeDirectoryTests

- (void)testDirectoryExists
{
  NSError *error = nil;
  NSString *directory = [FBXcodeDirectory.xcodeSelectFromCommandLine.xcodePath await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(directory);

  NSString *xctestPath = NSProcessInfo.processInfo.arguments[0];
  XCTAssertTrue([xctestPath hasPrefix:directory]);
}

@end
