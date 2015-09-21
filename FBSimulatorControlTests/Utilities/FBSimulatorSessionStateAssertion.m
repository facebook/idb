/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionStateAssertion.h"

#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>

@interface FBSimulatorSessionStateAssertion ()

@property (nonatomic, strong) FBSimulatorSessionState *state;

@end

@implementation FBSimulatorSessionStateAssertion

+ (instancetype)forState:(FBSimulatorSessionState *)state
{
  FBSimulatorSessionStateAssertion *assertion = [self new];
  assertion.state = state;
  return assertion;
}

- (void)assertChangesToSimulatorState:(NSArray *)states
{
  NSArray *actualStates = [self.state.changesToSimulatorState.reverseObjectEnumerator.allObjects valueForKey:@"simulatorState"];
  XCTAssertEqualObjects(actualStates, states);
}

@end
