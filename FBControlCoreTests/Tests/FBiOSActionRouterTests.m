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

@interface FBiOSActionRouterTests : XCTestCase

@property (nonatomic, strong, readwrite) id<FBiOSTarget> target;

@end

@implementation FBiOSActionRouterTests

+ (NSArray<id<FBiOSTargetAction>> *)actions
{
  return @[
    [FBTestLaunchConfiguration configurationWithTestBundlePath:@"/bar/bar"],
    [[[[[FBTestLaunchConfiguration configurationWithTestBundlePath:@"/aa"] withUITesting:YES] withTestHostPath:@"/baa"] withTimeout:12] withTestsToRun:[NSSet setWithArray:@[@"foo", @"bar"]]],
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
  FBiOSActionRouter *router = [FBiOSActionRouter routerForTarget:self.target actionClasses:FBiOSActionRouter.defaultActionClasses];
  NSArray<id<FBiOSTargetAction>> *actions = FBiOSActionRouterTests.actions;
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
