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

@interface FBXcodeDirectoryTests : XCTestCase

@end

@implementation FBXcodeDirectoryTests

- (void)testDirectoryExists
{
  NSError *error = nil;
  NSString *directory = [FBXcodeDirectory.xcodeSelectFromCommandLine xcodePathWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(directory);

  NSString *xctestPath = NSProcessInfo.processInfo.arguments[0];
  XCTAssertTrue([xctestPath hasPrefix:directory]);
}

@end
