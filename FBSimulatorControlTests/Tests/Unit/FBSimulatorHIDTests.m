/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorHID.h>

@interface FBSimulatorHIDTests : XCTestCase
@end

@implementation FBSimulatorHIDTests

#pragma mark API surface

- (void)testSendPurpleEventConvenienceWrapperExists
{
  XCTAssertTrue(
    [FBSimulatorHID instancesRespondToSelector:@selector(sendPurpleEvent:error:)],
    @"Convenience wrapper without timeout must remain available for callers that opt into the default behavior.");
}

- (void)testSendPurpleEventWithTimeoutMsExists
{
  XCTAssertTrue(
    [FBSimulatorHID instancesRespondToSelector:@selector(sendPurpleEvent:timeoutMs:error:)],
    @"Timeout-aware overload must be exposed for callers that need to bound the send.");
}

@end
