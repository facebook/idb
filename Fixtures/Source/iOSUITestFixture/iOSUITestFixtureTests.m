/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

// This test targets expects to be launched with Apple's TableSearch example application.
// Unfortunately it does not seem to be possible to build a UI Test target without some
// host application.
// This is the reason why there is this empty iOSUITestFixtureHost application target.

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
  // This does exist and should succeed.
  [XCUIApplication.new.tables.staticTexts[@"MacBook Pro"] tap];
}

- (void)testFailure
{
  // This does not exist and will fail.
  [XCUIApplication.new.tables.staticTexts[@"PowerBook"] tap];
}

@end
