/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

@interface MacUITestFixtureUITests : XCTestCase
@end

@implementation MacUITestFixtureUITests

- (void)setUp
{
  [super setUp];
  self.continueAfterFailure = NO;
  [[XCUIApplication new] launch];
}

- (void)testHelloWorld
{
  XCUIApplication *app = [XCUIApplication new];
  XCUIElement *textView = app.staticTexts[@"Copyright \u00A9 2017 Facebook. All rights reserved."];
  [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists = 1"]
            evaluatedWithObject:textView
                        handler:nil];
  [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists = 1"]
            evaluatedWithObject:app.buttons[@"Hello world"]
                        handler:nil];
  [app.menuItems[@"About MacUITestFixture"] click];
  [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end
