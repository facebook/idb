/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
