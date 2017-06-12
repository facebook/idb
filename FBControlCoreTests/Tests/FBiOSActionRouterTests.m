/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBiOSTargetDouble.h"
#import "FBiOSTargetActionDouble.h"

@interface FBiOSActionRouterTests : XCTestCase

@property (nonatomic, strong, readwrite) id<FBiOSTarget> target;

@end

@implementation FBiOSActionRouterTests

+ (NSArray<id<FBiOSTargetAction>> *)actions
{
  return @[
    [[FBiOSTargetActionDouble alloc] initWithIdentifier:@"foo" succeed:NO],
    [[FBiOSTargetActionDouble alloc] initWithIdentifier:@"bar" succeed:YES],
  ];
}

- (void)setUp
{
  FBiOSTargetDouble *target = [FBiOSTargetDouble new];
  target.udid = @"some-udid";
  self.target = target;
}

- (void)testCorrectlyDeflates
{
  NSArray<id<FBiOSTargetAction>> *actions = FBiOSActionRouterTests.actions;
  NSSet<Class> *actionClasses = [NSSet setWithArray:[actions valueForKey:@"class"]];
  FBiOSActionRouter *router = [FBiOSActionRouter routerForTarget:self.target actionClasses:actionClasses.allObjects];
  for (id<FBiOSTargetAction> action in actions) {
    NSDictionary<NSString *, id> *json = [router jsonFromAction:action];
    XCTAssertEqualObjects(json[@"action"], [action.class actionType]);
    XCTAssertEqualObjects(json[@"udid"], self.target.udid);
    NSError *error = nil;
    id<FBiOSTargetAction> deflated = [router actionFromJSON:json error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(action, deflated);
  }
}

@end
