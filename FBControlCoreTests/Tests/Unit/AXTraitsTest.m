/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <AXRuntime/AXTraits.h>

@interface AXTraitsTest : XCTestCase
@end

@implementation AXTraitsTest

- (void)testMappingNames
{
  NSDictionary<NSNumber *, NSString *> *mapping = AXTraitToNameMap();
  XCTAssertEqualObjects(mapping[@(AXTraitLink)], @"Link");
  XCTAssertEqualObjects(mapping[@(AXTraitButton)], @"Button");
}

@end
