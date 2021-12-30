/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

@interface MacUnitTestFixtureTests : XCTestCase

@end

@implementation MacUnitTestFixtureTests

- (void)setUp
{
  NSLog(@"Started running MacUnitTestFixtureTests");
}

- (void)testIsRunningOnIOS
{
  XCTAssertNotNil(NSClassFromString(@"UIView"));
}

- (void)testIsRunningInIOSApp
{
  XCTAssertNotNil([NSClassFromString(@"UIApplication") performSelector:@selector(sharedApplication)]);
}

- (void)testIsRunningOnMacOSX
{
  XCTAssertNotNil(NSClassFromString(@"NSView"));
}

- (void)testIsRunningInMacOSXApp
{
  XCTAssertNotNil([NSClassFromString(@"NSApplication") performSelector:@selector(sharedApplication)]);
}

- (void)testHostProcessIsXctest
{
  XCTAssertTrue([NSProcessInfo.processInfo.processName isEqualToString:@"xctest"]);
}

- (void)testHostProcessIsMobileSafari
{
  XCTAssertTrue([NSProcessInfo.processInfo.processName isEqualToString:@"MacCommonApp"]);
}

- (void)testPossibleCrashingOfHostProcess
{
  if ([NSProcessInfo.processInfo.environment[@"TEST_FIXTURE_SHOULD_CRASH"] boolValue]) {
    NSLog(@"'TEST_FIXTURE_SHOULD_CRASH' is True, aborting");
    abort();
  }
}

- (void)testPossibleStallingOfHostProcess
{
  if ([NSProcessInfo.processInfo.environment[@"TEST_FIXTURE_SHOULD_STALL"] boolValue]) {
    NSLog(@"'TEST_FIXTURE_SHOULD_STALL' is True, stalling");
    sleep(INT_MAX);
  }
}

- (void)testWillAlwaysPass
{
  // do nothing
}

- (void)testWillAlwaysFail
{
  XCTFail(@"This always fails");
}

- (void)testAsyncExpectationPassing
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Async expectation passed"];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    sleep(1);
    [expectation fulfill];
  });

  [self waitForExpectations:@[expectation] timeout:2];
}

- (void)testAsyncExpectationFailing
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Async expectation passed"];
  expectation.inverted = YES;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    sleep(1);
    [expectation fulfill];
  });

  [self waitForExpectations:@[expectation] timeout:2];
}

@end
