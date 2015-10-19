/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBInteractionAssertion.h"

#import <FBSimulatorControl/FBInteraction.h>

@interface FBInteractionAssertion ()

@property (nonatomic, strong, readwrite) XCTestCase *testCase;

@end

@implementation FBInteractionAssertion

+ (instancetype)withTestCase:(XCTestCase *)testCase
{
  FBInteractionAssertion *assertion = [self new];
  assertion.testCase = testCase;
  return assertion;
}

- (void)assertPerformSuccess:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];
  _XCTPrimitiveAssertTrue(self.testCase, success, "assertPerformSuccess:");
  _XCTPrimitiveAssertNil(self.testCase, error, "error");
}

@end
