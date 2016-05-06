/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

@interface SimpleTestTarget : XCTestCase

@end

@implementation SimpleTestTarget

- (void)setUp
{
  NSLog(@"Started running SimpleTestTarget");
}

- (void)testIsRunningOnIOS
{
  XCTAssertNotNil(NSClassFromString(@"UIView"));
}

- (void)testIsRunningOnMacOSX
{
  XCTAssertNotNil(NSClassFromString(@"NSView"));
}

- (void)testIsSafari
{
  XCTAssertTrue([NSProcessInfo.processInfo.processName isEqualToString:@"MobileSafari"]);
}

@end
