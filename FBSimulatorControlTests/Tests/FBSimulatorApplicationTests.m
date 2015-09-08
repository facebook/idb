/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import "FBSimulatorApplication.h"

@interface FBSimulatorApplicationTests : XCTestCase

@end

@implementation FBSimulatorApplicationTests

- (void)testFetchesSimulatorApplications
{
  NSArray *simulatorApplications = [FBSimulatorApplication simulatorSystemApplications];
  NSSet *names = [NSSet setWithArray:[simulatorApplications valueForKey:@"name"]];

  XCTAssertTrue([names containsObject:@"MobileSafari"]);
  XCTAssertTrue([names containsObject:@"Camera"]);
  XCTAssertTrue([names containsObject:@"Maps"]);
}

@end
