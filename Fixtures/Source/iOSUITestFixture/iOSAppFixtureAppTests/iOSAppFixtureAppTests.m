/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

@interface iOSAppFixtureAppTests : XCTestCase

@end

@implementation iOSAppFixtureAppTests

- (void)testWillAlwaysPass
{
  // do nothing
}

- (void)testWillAlwaysFail
{
  XCTFail(@"This always fails");
}

@end
