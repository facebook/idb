/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBControlCoreRunLoopTests : FBControlCoreValueTestCase

@end

@implementation FBControlCoreRunLoopTests

- (void)testNestedAwaiting
{
  FBFuture<NSNumber *> *future = [[FBFuture
    futureWithDelay:0.1 future:[FBFuture futureWithResult:@YES]]
    onQueue:dispatch_get_main_queue() map:^(id _) {
      return [[FBFuture futureWithDelay:0.1 future:[FBFuture futureWithResult:@YES]] await:nil];
    }];

  NSError *error = nil;
  BOOL succeeded = [future await:&error] != nil;
  XCTAssertTrue(succeeded);
  XCTAssertNil(error);
}

@end
