/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
