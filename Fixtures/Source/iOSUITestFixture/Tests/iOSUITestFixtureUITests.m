/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

@interface iOSUITestFixtureUITests : XCTestCase
@end

@implementation iOSUITestFixtureUITests

- (void)setUp
{
  [super setUp];
  self.continueAfterFailure = NO;
}

- (void)testHelloWorld
{
  [[XCUIApplication new] launch];
  XCUIApplication *app = [XCUIApplication new];
  XCUIElement *button = app.buttons[@"Welcome"];
  [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists = 1 && hittable = 1"]
            evaluatedWithObject:button
                        handler:^BOOL{
                          [button tap];
                          return YES;
                        }];
  [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists = 1"]
            evaluatedWithObject:app.staticTexts[@"Hello world"]
                        handler:nil];
  [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testThatFails
{
  XCUIApplication *app = [XCUIApplication new];
  XCTAssertTrue(app.state == XCUIApplicationStateRunningForeground);
}

- (void)testThatPasses1
{
  XCUIApplication *app = [XCUIApplication new];
  XCTAssertFalse(app.state == XCUIApplicationStateRunningForeground);
}

- (void)testThatPasses2
{
  [[XCUIApplication new] launch];
  XCUIApplication *app = [XCUIApplication new];
  XCTAssertTrue(app.state == XCUIApplicationStateRunningForeground);
}

@end
