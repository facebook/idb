/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBGDBClientTests : XCTestCase

@end

@implementation FBGDBClientTests

- (void)testStringConverstion
{
  NSString *input = @"hello";
  NSString *encoded = [FBGDBClient hexEncode:input];
  NSString *output = [FBGDBClient hexDecode:encoded];
  XCTAssertEqualObjects(input, output);
}

@end
