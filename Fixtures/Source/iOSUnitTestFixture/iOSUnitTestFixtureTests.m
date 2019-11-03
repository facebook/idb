/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

@interface iOSUnitTestFixtureTests : XCTestCase

@end

@implementation iOSUnitTestFixtureTests

- (void)setUp
{
  NSLog(@"Started running iOSUnitTestFixtureTests");
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
  XCTAssertTrue([NSProcessInfo.processInfo.processName isEqualToString:@"MobileSafari"]);
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

@end
