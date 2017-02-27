/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

@interface iOSUITestFixtureTests : XCTestCase

@end

@implementation iOSUITestFixtureTests

- (void)setUp
{
  [super setUp];

  self.continueAfterFailure = NO;
  [XCUIApplication.new launch];
}

- (void)testSuccess
{
  [XCUIApplication.new.buttons[@"PING"] tap];
  [XCUIApplication.new.buttons[@"PONG"] tap];
}

- (void)testFailure
{
  [XCUIApplication.new.buttons[@"PONG"] tap];
  [XCUIApplication.new.buttons[@"PING"] tap];
}

@end
